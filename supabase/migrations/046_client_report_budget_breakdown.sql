-- ============================================================
-- Adds finer-grained budget tracking to اطلاعات پایه پروژه, alongside
-- the existing contract_initial_amount_* / contract_current_amount_* /
-- revised_budget_amount_* (migrations 006, 040):
--
--   - budget_absorption_base_*/_revision_*: splits the cumulative
--     absorption into what was drawn against the ORIGINAL ceiling
--     ("بدون تعدیل") vs. specifically against a بودجه اصلاحی's own
--     increment ("فقط تعدیل") — contract_current_amount_* stays the
--     one cumulative total used everywhere already (computeProjectStatusMetrics
--     included); these two are a reporting breakdown of it, not a
--     replacement.
--   - budget_annual_forecast_*/budget_annual_absorption_*: the same
--     planned-vs-actual pair but scoped to the current فیسکال/budget
--     year instead of the contract's whole cumulative lifetime —
--     every other amount on this form is cumulative-since-start, this
--     is the first per-year figure.
--
-- Same units as every other amount column here: Rial columns in
-- billion Rial, EUR columns in million Euro (see contract_current_amount_rial's
-- own column comment, migration 006).
-- ============================================================

alter table client_reports
    add column if not exists budget_absorption_base_rial numeric,
    add column if not exists budget_absorption_base_eur numeric,
    add column if not exists budget_absorption_revision_rial numeric,
    add column if not exists budget_absorption_revision_eur numeric,
    add column if not exists budget_annual_forecast_rial numeric,
    add column if not exists budget_annual_forecast_eur numeric,
    add column if not exists budget_annual_absorption_rial numeric,
    add column if not exists budget_annual_absorption_eur numeric;

comment on column client_reports.budget_absorption_base_rial is 'مبلغ جذب بودجه کل (ریالی) — بدون تعدیل: portion of the cumulative absorption drawn against the original ceiling, billion Rial.';
comment on column client_reports.budget_absorption_base_eur is 'مبلغ جذب بودجه کل (ارزی) — بدون تعدیل, million Euro.';
comment on column client_reports.budget_absorption_revision_rial is 'میزان جذب بودجه کل (ریالی) — فقط تعدیل: portion of the cumulative absorption drawn specifically against a بودجه اصلاحی increment, billion Rial.';
comment on column client_reports.budget_absorption_revision_eur is 'میزان جذب بودجه کل (ارزی) — فقط تعدیل, million Euro.';
comment on column client_reports.budget_annual_forecast_rial is 'پیش‌بینی بودجه سالانه (ریالی) — planned budget for the current year, billion Rial (not cumulative).';
comment on column client_reports.budget_annual_forecast_eur is 'پیش‌بینی بودجه سالانه (ارزی), million Euro (not cumulative).';
comment on column client_reports.budget_annual_absorption_rial is 'میزان جذب سالانه بودجه (ریالی) — actual absorption for the current year, billion Rial (not cumulative).';
comment on column client_reports.budget_annual_absorption_eur is 'میزان جذب سالانه بودجه (ارزی), million Euro (not cumulative).';
