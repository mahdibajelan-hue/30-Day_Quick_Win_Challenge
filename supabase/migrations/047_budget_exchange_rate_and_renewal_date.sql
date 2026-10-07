-- ============================================================
-- Refines the budget-absorption split from migration 046 and adds the
-- fields needed to turn «از پیمان» / annual-absorption on the project
-- card into ONE percentage each (combining Rial + EUR via the contract's
-- own exchange rate) instead of two separate, hard-to-reconcile numbers:
--
--   - budget_absorption_base_*/_revision_* (046) keep their column names
--     but are re-scoped: base is now explicitly «اصل و اضافه‌کاری»
--     (the base contract amount PLUS billed overtime/extra-work), and
--     revision is now the broader «تعدیل، توقف، خسارت و ...» bucket
--     (price adjustment, suspension costs, damages, etc.) rather than
--     just a تعدیل-only figure. Their SUM is «سرمایه‌گذاری کل پروژه»
--     — see computeProjectStatusMetrics's totalInvestedRial/Eur.
--   - contract_exchange_rate_rial_per_eur: Rial per 1 EUR, as quoted in
--     the contract itself — used ONLY to equalize an EUR amount into a
--     Rial-equivalent for percentage math (از پیمان و جذب سالانه),
--     never to convert the raw amounts shown on the card (those stay
--     reported per-currency, side by side).
--   - latest_renewal_date: «تاریخ آخرین تمدید», distinct from the
--     already-existing latest_extension_end_date («تاریخ آخرین
--     تطویل» — a formal schedule extension). A تمدید is a separate
--     administrative renewal (e.g. of the contract's own validity or a
--     guarantee), tracked alongside it rather than replacing it.
-- ============================================================

alter table client_reports
    add column if not exists contract_exchange_rate_rial_per_eur numeric,
    add column if not exists latest_renewal_date date;

comment on column client_reports.contract_exchange_rate_rial_per_eur is 'نرخ تسعیر ارز در پیمان — Rial per 1 EUR, as agreed in the contract. Used only to equalize budget_absorption_*/contract_initial_amount_*/budget_annual_*_eur into a Rial-equivalent for percentage math on the project card (computeProjectStatusMetrics); raw amounts are still reported per-currency, never auto-converted for display.';
comment on column client_reports.latest_renewal_date is 'تاریخ آخرین تمدید — latest administrative renewal date (e.g. of the contract''s own validity or a guarantee), distinct from latest_extension_end_date (تاریخ آخرین تطویل, a formal schedule extension). Null means no renewal recorded.';

comment on column client_reports.budget_absorption_base_rial is 'مبلغ جذب بودجه کل (ریالی) — اصل و اضافه‌کاری: the base contract amount absorbed plus billed overtime/extra-work, billion Rial. Compared against contract_initial_amount_rial (combined with the EUR side via contract_exchange_rate_rial_per_eur) for the «از پیمان» percentage, capped at 125%.';
comment on column client_reports.budget_absorption_base_eur is 'مبلغ جذب بودجه کل (ارزی) — اصل و اضافه‌کاری, million Euro. See budget_absorption_base_rial.';
comment on column client_reports.budget_absorption_revision_rial is 'مبلغ جذب بودجه کل (ریالی) — تعدیل، توقف، خسارت و ...: everything absorbed OUTSIDE the اصل‌و‌اضافه‌کاری bucket (price adjustment, suspension costs, damages, etc.), billion Rial. budget_absorption_base_rial + this = سرمایه‌گذاری کل پروژه (totalInvestedRial).';
comment on column client_reports.budget_absorption_revision_eur is 'مبلغ جذب بودجه کل (ارزی) — تعدیل، توقف، خسارت و ..., million Euro. See budget_absorption_revision_rial.';
