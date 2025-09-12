
# Design-EMI Real Estate Model (Verbose, Tweakable)
# -------------------------------------------------
# See in-notebook version for comments. This file is the same code packaged for you to tweak.

import math
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import copy

try:
    import numpy_financial as npf
    HAS_NPFIN = True
except Exception:
    HAS_NPFIN = False

@dataclass
class Config:
    base_total_rs: float = 4.26e7
    possession_charges_rs: float = 0.103e7
    early_exit_fee_rs: float = 0.08e7
    annual_rate: float = 0.08
    full_emi_tenure_years: int = 20
    switch_to_full_emi_month: int = 36
    demands: Tuple[Tuple[int, str, float], ...] = ()
    equity_indices: Tuple[int, ...] = (0,)
    optimistic_map: Dict[int, float] = None
    realistic_map: Dict[int, float] = None
    pessimistic_map: Dict[int, float] = None
    pre_emi_choices_rs: Tuple[int, ...] = (30000, 100000, 200000, 300000)
    horizons_years: Tuple[int, ...] = (1, 2, 3, 4, 5, 6)
    # If True, unpaid interest capitalizes into principal monthly (interest-on-interest)
    capitalize_unpaid_interest: bool = True

def make_default_config() -> Config:
    cfg = Config()
    base = cfg.base_total_rs
    cfg.demands = (
        (0,  "Booking (10% equity)",  base * 0.10),
        (6,  "Tranche 1 (15%)",       base * 0.15),
        (12, "Tranche 2 (20%)",       base * 0.20),
        (18, "Tranche 3 (20%)",       base * 0.20),
        (24, "Tranche 4 (15%)",       base * 0.15),
        (30, "Tranche 5 (10%)",       base * 0.10),
    )
    cfg.optimistic_map = {1: 0.0, 2: 0.0, 3: "2x", 4: 0.12, 5: 0.10, 6: 0.10}
    cfg.realistic_map  = {1: 0.0, 2: 0.0, 3: 0.15, 4: 0.12, 5: 0.10, 6: 0.10}
    # Pessimistic: no appreciation by year 3, modest thereafter
    cfg.pessimistic_map = {1: 0.0, 2: 0.0, 3: 0.00, 4: 0.04, 5: 0.04, 6: 0.04}
    return cfg

def monthly_rate(annual: float) -> float:
    return annual / 12.0

def full_emi(principal: float, annual: float, years: int) -> float:
    r = monthly_rate(annual); n = years * 12
    if r == 0: return principal / n
    return principal * r * (1 + r) ** n / ((1 + r) ** n - 1)

def xirr(dates: List[pd.Timestamp], amounts: List[float]) -> Optional[float]:
    if HAS_NPFIN:
        try:
            return npf.xirr(amounts, dates)
        except Exception:
            pass
    t0 = dates[0]
    ts = np.array([(d - t0).days / 365.0 for d in dates], dtype=float)
    cfs = np.array(amounts, dtype=float)
    r = 0.2
    for _ in range(200):
        denom = (1 + r) ** ts
        f = np.sum(cfs / denom)
        df = np.sum(-ts * cfs / ((1 + r) ** (ts + 1)))
        if abs(df) < 1e-12: break
        new_r = r - f / df
        if abs(new_r - r) < 1e-8: return new_r
        r = new_r
    return None

class DesignEMIModel:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.month_demands = {}
        for i, (m, lbl, amt) in enumerate(cfg.demands):
            self.month_demands.setdefault(m, []).append((i, lbl, amt))

    def sale_price(self, year: int, mode: str) -> float:
        base = self.cfg.base_total_rs
        if mode == "optimistic":
            curve = self.cfg.optimistic_map
            factor = curve[year]
            if year <= 2: return base
            if year == 3 and factor == "2x": return base * 2.0
            if isinstance(factor, float): return base * ((1 + factor) ** year)
            return base
        elif mode == "realistic":
            curve = self.cfg.realistic_map
            factor = curve[year]
            if year <= 2: return base
            return base * ((1 + factor) ** year)
        elif mode == "pessimistic":
            curve = self.cfg.pessimistic_map
            factor = curve[year]
            if year <= 2: return base
            return base * ((1 + factor) ** year)
        else:
            raise ValueError("mode must be 'optimistic', 'realistic', or 'pessimistic'")

    def simulate_year(self, pre_emi_rs: float, year: int):
        months = year * 12
        r_m = monthly_rate(self.cfg.annual_rate)
        principal = 0.0; accrued_unpaid = 0.0
        cash_equity = 0.0; cash_emis = 0.0
        full_emi_val = None
        for m in range(0, months + 1):
            if m in self.month_demands:
                for idx, label, amt in self.month_demands[m]:
                    if idx in self.cfg.equity_indices: cash_equity += amt
                    else: principal += amt
            interest_due = principal * r_m
            if m == self.cfg.switch_to_full_emi_month:
                full_emi_val = full_emi(principal, self.cfg.annual_rate, self.cfg.full_emi_tenure_years)
            if m > 0: payment = pre_emi_rs if m <= self.cfg.switch_to_full_emi_month else full_emi_val
            else:     payment = 0.0
            interest_paid = min(payment, interest_due)
            unpaid_interest = max(0.0, interest_due - payment)
            principal_repaid = max(0.0, payment - interest_due)
            if self.cfg.capitalize_unpaid_interest:
                principal += unpaid_interest
            else:
                accrued_unpaid += unpaid_interest
            principal = max(0.0, principal - principal_repaid)
            if m > 0 and payment > 0: cash_emis += payment
        cash_possession = self.cfg.possession_charges_rs if months >= self.cfg.switch_to_full_emi_month else 0.0
        loan_closure = principal + accrued_unpaid
        return {
            "year": year,
            "loan_closure_rs": loan_closure,
            "cash_outflow_rs": cash_equity + cash_emis + cash_possession,
        }

    def cashflow_pnl_table(self, pre_emi_rs: float, mode: str) -> pd.DataFrame:
        rows = []
        for y in self.cfg.horizons_years:
            st = self.simulate_year(pre_emi_rs, y)
            sale = 0.0 if y < 3 else self.sale_price(y, mode)
            # For years 1-2, show negative P&L equal to cash outflows
            pnl = (-st["cash_outflow_rs"]) if y < 3 else (sale - st["loan_closure_rs"] - st["cash_outflow_rs"])
            rows.append({
                "Year": y,
                "Cash_Outflow(Cr)": st["cash_outflow_rs"] / 1e7,
                "Loan_Balance(Cr)": st["loan_closure_rs"] / 1e7,
                "Sale_Price(Cr)": sale / 1e7,
                "P&L(Cr)": (pnl / 1e7),
            })
        return pd.DataFrame(rows)

    def annual_metrics_dataframe(self, pre_emi_rs: float) -> pd.DataFrame:
        """Build a long-form DataFrame with P&L and XIRR for each year and mode.
        Columns: Year, Mode, Cash_Outflow(Cr), Loan_Balance(Cr), Sale_Price(Cr), P&L(Cr), XIRR(%)
        """
        modes = ["optimistic", "realistic", "pessimistic"]
        all_rows: List[Dict[str, float]] = []
        for mode in modes:
            for y in self.cfg.horizons_years:
                st = self.simulate_year(pre_emi_rs, y)
                sale = 0.0 if y < 3 else self.sale_price(y, mode)
                pnl = (-st["cash_outflow_rs"]) if y < 3 else (sale - st["loan_closure_rs"] - st["cash_outflow_rs"])
                irr_pct = None
                if y >= 3:
                    dates, flows, _ = self.realized_cashflows(pre_emi_rs, y, mode)
                    irr = xirr(dates, flows)
                    irr_pct = (irr * 100.0) if irr is not None else None
                all_rows.append({
                    "Year": y,
                    "Mode": mode,
                    "Cash_Outflow(Cr)": st["cash_outflow_rs"] / 1e7,
                    "Loan_Balance(Cr)": st["loan_closure_rs"] / 1e7,
                    "Sale_Price(Cr)": sale / 1e7,
                    "P&L(Cr)": pnl / 1e7,
                    "XIRR(%)": irr_pct,
                })
        return pd.DataFrame(all_rows)

    def plot_pnl_and_xirr(self, pre_emi_rs: float, out_path: str = "outputs/pnl_xirr.png") -> str:
        """Plot P&L and XIRR over years for all scenarios and save to a file.
        Returns the output path.
        """
        df = self.annual_metrics_dataframe(pre_emi_rs)
        years = sorted(df["Year"].unique())
        modes = ["optimistic", "realistic", "pessimistic"]

        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)

        # Left: P&L
        ax = axes[0]
        for mode in modes:
            sub = df[df["Mode"] == mode]
            ax.plot(sub["Year"], sub["P&L(Cr)"], marker="o", label=mode)
        ax.set_title("P&L over Years (Cr)")
        ax.set_xlabel("Year")
        ax.set_ylabel("P&L (Cr)")
        ax.axhline(0, color="gray", linewidth=0.8)
        ax.legend(title="Scenario")

        # Right: XIRR
        ax = axes[1]
        for mode in modes:
            sub = df[df["Mode"] == mode]
            ax.plot(sub["Year"], sub["XIRR(%)"], marker="o", label=mode)
        ax.set_title("XIRR over Years (%)")
        ax.set_xlabel("Year")
        ax.set_ylabel("XIRR (%)")
        ax.legend(title="Scenario")

        plt.savefig(out_path, dpi=150)
        plt.close(fig)
        return out_path

    def clone_non_leveraged(self) -> "DesignEMIModel":
        """Return a new model where all demands are treated as equity (no loan)."""
        new_cfg = copy.deepcopy(self.cfg)
        num_demands = len(new_cfg.demands)
        new_cfg.equity_indices = tuple(range(num_demands))
        return DesignEMIModel(new_cfg)

    def plot_four_cases(self) -> List[str]:
        """Plot the requested four cases and return list of output paths.
        Cases:
          1) Leverage - 30K EMI
          2) Leverage - 1L EMI
          3) Leverage - 3L EMI
          4) Non Leveraged (all tranches equity; no EMIs)
        """
        outputs = []
        cases = [
            (self, 30000, "outputs/pnl_xirr_leverage_30k.png"),
            (self, 100000, "outputs/pnl_xirr_leverage_100k.png"),
            (self, 300000, "outputs/pnl_xirr_leverage_300k.png"),
        ]
        # Non-leveraged: no loan, no EMI payments
        non_lev_model = self.clone_non_leveraged()
        cases.append((non_lev_model, 0, "outputs/pnl_xirr_non_leveraged.png"))

        for mdl, pre_emi, path in cases:
            outputs.append(mdl.plot_pnl_and_xirr(pre_emi, out_path=path))
        return outputs

    def plot_scenario_with_cases(self, mode: str) -> str:
        """Create a figure for a single scenario with four case lines (P&L and XIRR)."""
        assert mode in {"optimistic", "realistic", "pessimistic"}
        cases = [
            (self, 30000, "Leverage 30k"),
            (self, 100000, "Leverage 100k"),
            (self, 300000, "Leverage 300k"),
            (self.clone_non_leveraged(), 0, "Non-leveraged"),
        ]
        out_path = f"outputs/pnl_xirr_{mode}_cases.png"
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)

        fig, ax = plt.subplots(1, 1, figsize=(10, 5), constrained_layout=True)

        # P&L (annotate with XIRR% where available)
        for mdl, pre_emi, label in cases:
            df = mdl.annual_metrics_dataframe(pre_emi)
            sub = df[df["Mode"] == mode]
            ax.plot(sub["Year"], sub["P&L(Cr)"], marker="o", label=label)
            # Label each point with P&L and XIRR% (when defined)
            for x, pnl, irr in zip(sub["Year"], sub["P&L(Cr)"], sub["XIRR(%)"]):
                if pd.notnull(irr):
                    txt = f"{pnl:.2f} | {irr:.1f}%"
                else:
                    txt = f"{pnl:.2f}"
                ax.annotate(txt, (x, pnl), textcoords="offset points", xytext=(0,6), ha="center", fontsize=8)
        ax.set_title(f"P&L over Years (Cr) - {mode} (labels include XIRR%)")
        ax.set_xlabel("Year")
        ax.set_ylabel("P&L (Cr)")
        ax.axhline(0, color="gray", linewidth=0.8)
        ax.legend(title="Case")

        # Add assumed price growth/CAGR info as a figure-level note
        if mode == "optimistic":
            curve = self.cfg.optimistic_map
        elif mode == "realistic":
            curve = self.cfg.realistic_map
        else:
            curve = self.cfg.pessimistic_map

        def _fmt(v):
            if isinstance(v, str):
                return v
            return f"{v*100:.0f}%"

        growth_text = ", ".join([f"Y{yr}:{_fmt(curve[yr])}" for yr in sorted(curve.keys())])
        cap_text = "On" if self.cfg.capitalize_unpaid_interest else "Off"
        fig.suptitle(
            f"Scenario: {mode.capitalize()}  |  Assumed price growth: {growth_text}  |  Capitalized interest: {cap_text}",
            fontsize=11,
        )

        plt.savefig(out_path, dpi=150)
        plt.close(fig)
        return out_path

    def plot_all_scenarios_separate(self) -> List[str]:
        paths = []
        for mode in ["optimistic", "realistic", "pessimistic"]:
            paths.append(self.plot_scenario_with_cases(mode))
        return paths

    def yearly_loan_cost_emi_table(self, pre_emi_rs: float, mode: str = "realistic") -> pd.DataFrame:
        """Return a yearly table for the given mode with:
        - Property cost paid-to-date (sum of demands to date)
        - Loan disbursed-to-date (sum of loan-funded demands to date)
        - Loan balance (principal + accrued unpaid interest)
        - EMI paid this year and cumulative (excludes possession charges)
        - P&L per year (Cr): negative of cash outflow for years < 3; sale - loan_close - cash_outflow for years >= 3
        Units are converted to Cr for readability.
        """
        assert mode in {"optimistic", "realistic", "pessimistic"}
        max_years = max(self.cfg.horizons_years)
        months_max = max_years * 12
        r_m = monthly_rate(self.cfg.annual_rate)

        # Time series containers (indexed by month)
        prop_cost_cum = np.zeros(months_max + 1)
        loan_disbursed_cum = np.zeros(months_max + 1)
        emi_cum = np.zeros(months_max + 1)
        loan_balance_series = np.zeros(months_max + 1)

        principal = 0.0
        accrued_unpaid = 0.0
        full_emi_val = None

        for m in range(0, months_max + 1):
            # Add demands occurring at this month
            if m in self.month_demands:
                for idx, label, amt in self.month_demands[m]:
                    prop_cost_cum[m] += amt
                    if idx not in self.cfg.equity_indices:
                        principal += amt
                        loan_disbursed_cum[m] += amt
            # Carry forward cumulative sums
            if m > 0:
                prop_cost_cum[m] += prop_cost_cum[m - 1]
                loan_disbursed_cum[m] += loan_disbursed_cum[m - 1]
                emi_cum[m] = emi_cum[m - 1]

            # Interest accrual and payments
            interest_due = principal * r_m
            if m == self.cfg.switch_to_full_emi_month:
                full_emi_val = full_emi(principal, self.cfg.annual_rate, self.cfg.full_emi_tenure_years)
            if m > 0:
                payment = pre_emi_rs if m <= self.cfg.switch_to_full_emi_month else full_emi_val
            else:
                payment = 0.0
            interest_paid = min(payment, interest_due)
            unpaid_interest = max(0.0, interest_due - payment)
            principal_repaid = max(0.0, payment - interest_due)
            if self.cfg.capitalize_unpaid_interest:
                principal += unpaid_interest
            else:
                accrued_unpaid += unpaid_interest
            principal = max(0.0, principal - principal_repaid)
            if m > 0 and payment > 0:
                emi_cum[m] += payment

            loan_balance_series[m] = principal + accrued_unpaid

        # Build yearly rows
        rows: List[Dict[str, float]] = []
        for y in self.cfg.horizons_years:
            m_end = y * 12
            m_prev = (y - 1) * 12
            # P&L via existing simulate_year and sale_price
            st = self.simulate_year(pre_emi_rs, y)
            sale = 0.0 if y < 3 else self.sale_price(y, mode)
            pnl_rs = (-st["cash_outflow_rs"]) if y < 3 else (sale - st["loan_closure_rs"] - st["cash_outflow_rs"])
            rows.append({
                "Year": y,
                "Property_Cost_ToDate(Cr)": prop_cost_cum[m_end] / 1e7,
                "Loan_Disbursed_ToDate(Cr)": loan_disbursed_cum[m_end] / 1e7,
                "Loan_Balance(Cr)": loan_balance_series[m_end] / 1e7,
                "EMI_Paid_This_Year(Cr)": (emi_cum[m_end] - (emi_cum[m_prev] if y > 1 else 0.0)) / 1e7,
                "EMI_Paid_Cumulative(Cr)": emi_cum[m_end] / 1e7,
                "P&L(Cr)": pnl_rs / 1e7,
            })
        return pd.DataFrame(rows)

    def realized_cashflows(self, pre_emi_rs: float, exit_year: int, mode: str):
        dates = []; flows = []
        start = pd.to_datetime("2025-09-01")
        months = exit_year * 12
        r_m = monthly_rate(self.cfg.annual_rate)
        principal = 0.0; accrued_unpaid = 0.0; full_emi_val = None
        for m in range(0, months + 1):
            date = start + pd.DateOffset(months=m)
            if m in self.month_demands:
                for idx, label, amt in self.month_demands[m]:
                    if idx in self.cfg.equity_indices: dates.append(date); flows.append(-amt)
                    else: principal += amt
            interest_due = principal * r_m
            if m == self.cfg.switch_to_full_emi_month:
                full_emi_val = full_emi(principal, self.cfg.annual_rate, self.cfg.full_emi_tenure_years)
            if m > 0: payment = pre_emi_rs if m <= self.cfg.switch_to_full_emi_month else full_emi_val
            else:     payment = 0.0
            interest_paid = min(payment, interest_due)
            unpaid_interest = max(0.0, interest_due - payment)
            principal_repaid = max(0.0, payment - interest_due)
            if self.cfg.capitalize_unpaid_interest:
                principal += unpaid_interest
            else:
                accrued_unpaid += unpaid_interest
            principal = max(0.0, principal - principal_repaid)
            if m > 0 and payment > 0: dates.append(date); flows.append(-payment)
        if months >= self.cfg.switch_to_full_emi_month:
            dates.append(start + pd.DateOffset(months=self.cfg.switch_to_full_emi_month))
            flows.append(-self.cfg.possession_charges_rs)
        sale = self.sale_price(exit_year, mode)
        loan_close = principal + accrued_unpaid
        inflow = sale - loan_close - self.cfg.early_exit_fee_rs
        dates.append(start + pd.DateOffset(months=months)); flows.append(inflow)
        return dates, flows, {"SalePrice_rs": sale, "LoanClosure_rs": loan_close, "NetInflow_rs": inflow}

if __name__ == "__main__":
    CFG = make_default_config()
    model = DesignEMIModel(CFG)
    # Generate only the three scenario graphs (each includes all four cases)
    scenario_files = model.plot_all_scenarios_separate()
    for f in scenario_files:
        print(f"Saved plot to: {f}")
    # Print the yearly table for the realistic case at 100k pre-EMI
    df_realistic = model.yearly_loan_cost_emi_table(100000, mode="realistic")
    print("\nRealistic case yearly breakdown (100k pre-EMI):")
    print(df_realistic.to_string(index=False))
