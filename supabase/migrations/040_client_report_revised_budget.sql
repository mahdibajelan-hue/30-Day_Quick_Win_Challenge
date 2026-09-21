-- ============================================================
-- «اگر بودجه اولیه ۱۰۰٪ شده و تقاضای بودجه اصلاحی داده شده، میزان مصرف
-- نسبت به آن داده شود» — client_reports had no way to record a revised
-- budget ceiling at all: contract_initial_amount_* is the original
-- budget and contract_current_amount_* (labeled «میزان جذب» in the
-- form) is actual absorption to date, but nothing captured a NEW,
-- larger authorized ceiling after a بودجه اصلاحی — the exact budget
-- counterpart of latest_extension_end_date (migration 031), which
-- already does this for time.
--
-- Absorption % on the project cards now divides by
-- revised_budget_amount_* when set, falling back to
-- contract_initial_amount_* otherwise — same fallback shape
-- computeProjectStatusMetrics already uses for the extended-schedule
-- percentage against latest_extension_end_date.
-- ============================================================

alter table client_reports
    add column if not exists revised_budget_amount_rial numeric,
    add column if not exists revised_budget_amount_eur numeric;

comment on column client_reports.revised_budget_amount_rial is 'New authorized budget ceiling (billion Rial) after a بودجه اصلاحی, if any. Null means no revision has been requested/approved — absorption % falls back to contract_initial_amount_rial.';
comment on column client_reports.revised_budget_amount_eur is 'New authorized budget ceiling (million Euro) after a بودجه اصلاحی, if any. Null means no revision has been requested/approved — absorption % falls back to contract_initial_amount_eur.';
