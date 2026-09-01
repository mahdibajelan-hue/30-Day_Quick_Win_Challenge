-- ============================================================
-- Migration: split client_reports' contract amount into a Rial
-- portion and a foreign-currency (Euro) portion, since several
-- projects' contracts are priced partly in each. Rial is entered in
-- billion Rial, Euro in million Euro.
--
-- contract_initial_amount / contract_current_amount (single Rial-only
-- figures) are now deprecated — the app no longer reads or writes
-- them — but are left in place rather than dropped, matching this
-- repo's convention of not removing columns from a production schema
-- I can't directly inspect.
-- ============================================================

alter table client_reports
    add column if not exists contract_initial_amount_rial numeric,
    add column if not exists contract_initial_amount_eur numeric,
    add column if not exists contract_current_amount_rial numeric,
    add column if not exists contract_current_amount_eur numeric;

comment on column client_reports.contract_initial_amount_rial is 'billion Rial';
comment on column client_reports.contract_initial_amount_eur is 'million Euro';
comment on column client_reports.contract_current_amount_rial is 'billion Rial';
comment on column client_reports.contract_current_amount_eur is 'million Euro';
