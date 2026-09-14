-- The overall «پیشرفت برنامه‌ای کل» / «پیشرفت واقعی کل» figures used to be a
-- plain, equally-weighted average of whichever E/P/C discipline fields a
-- contract type shows — which doesn't match a real weighted S-curve once a
-- project's disciplines don't carry equal shares of the contract (e.g. an
-- EPC job where construction is 60% of value and engineering is 10%). These
-- three columns let the PM enter each discipline's actual share (%) of the
-- contract so the frontend can compute a properly weighted overall progress
-- instead. Nullable and non-destructive: existing rows keep reading as an
-- equal-weight average until a weight is entered for that project.

alter table client_reports
    add column if not exists progress_engineering_weight numeric,
    add column if not exists progress_procurement_weight numeric,
    add column if not exists progress_construction_weight numeric;

comment on column client_reports.progress_engineering_weight is 'Engineering''s share (%) of total contract value, entered by the PM; used to weight progress_engineering(_planned) into progress_planned/progress_physical. Null means "not yet entered" — treated as equal weight with the other shown disciplines.';
comment on column client_reports.progress_procurement_weight is 'Procurement''s share (%) of total contract value, entered by the PM; used to weight progress_procurement(_planned) into progress_planned/progress_physical. Null means "not yet entered" — treated as equal weight with the other shown disciplines.';
comment on column client_reports.progress_construction_weight is 'Construction''s share (%) of total contract value, entered by the PM; used to weight progress_construction(_planned) into progress_planned/progress_physical. Null means "not yet entered" — treated as equal weight with the other shown disciplines.';
