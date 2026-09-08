-- Redesign backlog (P0 round 2): «فرم اطلاعات پایه پروژه» now captures the
-- forecast completion date and per-discipline (E/P/C) planned+actual
-- progress that used to live scattered across check_ins (a per-organization,
-- per-period field) and a single unpaired progress_engineering/procurement/
-- construction reading. Consolidating them here means:
--   * forecast_completion_date moves to client_reports — it's the PMO's one
--     official schedule figure for the whole project, not something each of
--     the three organizations should re-report every check-in.
--   * progress_engineering/procurement/construction (already existing,
--     single-value columns) become the "actual" counterpart of three new
--     "*_planned" columns, so each discipline finally has the planned/actual
--     pair the overall progress_planned/progress_physical columns already had.
--
-- Deliberately NON-DESTRUCTIVE: check_ins.planned_progress/physical_progress/
-- forecast_completion_date/work_fronts and the risk probability/impact/level
-- keys inside check_ins.risks are no longer written by the frontend after
-- this change, but nothing here drops them — old rows keep their historical
-- values exactly as before.

alter table client_reports
    add column if not exists forecast_completion_date date,
    add column if not exists progress_engineering_planned numeric,
    add column if not exists progress_procurement_planned numeric,
    add column if not exists progress_construction_planned numeric;

comment on column client_reports.forecast_completion_date is 'PMO''s current forecast completion date for the project as a whole (moved here from check_ins.forecast_completion_date, which used to be reported separately per organization per period).';
comment on column client_reports.progress_engineering is 'Actual/physical engineering progress (%), paired with progress_engineering_planned.';
comment on column client_reports.progress_procurement is 'Actual/physical procurement progress (%), paired with progress_procurement_planned.';
comment on column client_reports.progress_construction is 'Actual/physical construction progress (%), paired with progress_construction_planned.';
comment on column client_reports.progress_engineering_planned is 'Planned engineering progress (%), paired with progress_engineering (actual). Shown only for contract types that include an engineering scope (E, EPC, یا سایر).';
comment on column client_reports.progress_procurement_planned is 'Planned procurement progress (%), paired with progress_procurement (actual). Shown only for contract types that include a procurement scope (PC, EPC, یا سایر).';
comment on column client_reports.progress_construction_planned is 'Planned construction progress (%), paired with progress_construction (actual). Shown only for contract types that include a construction scope (PC, C, EPC, یا سایر).';
