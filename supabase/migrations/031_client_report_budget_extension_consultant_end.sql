-- Feeds the new «آخرین وضعیت پروژه‌ها» visual report, which needs two things
-- client_reports doesn't capture yet (budget absorption itself already
-- exists as cr_amount_current_rial/eur — labeled «میزان جذب» in the form,
-- against cr_amount_initial_rial/eur — no new column needed there):
--   * The consultant's own contract end date — contract_end_date already
--     exists but is the CONTRACTOR's (the whole form is framed around the
--     پیمانکار's construction contract); the consultant's advisory
--     contract commonly runs on a different schedule.
--   * The latest approved time extension's new completion date, so
--     "زمان باقیمانده" can be reported against the currently-approved
--     schedule, not just the original contract_end_date. Null means no
--     extension has been approved yet.

alter table client_reports
    add column if not exists consultant_contract_end_date date,
    add column if not exists latest_extension_end_date date;

comment on column client_reports.consultant_contract_end_date is 'End date of the consultant''s own advisory contract — distinct from contract_end_date, which is the contractor''s.';
comment on column client_reports.latest_extension_end_date is 'New completion date approved by the latest contract time extension (تطویل), if any. Null means no extension has been approved — "زمان باقیمانده" reporting falls back to contract_end_date.';
