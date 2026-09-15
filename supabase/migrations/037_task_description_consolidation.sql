-- The five separate CAPA fields on a task (root_cause/corrective_action/
-- preventive_action/latest_update/next_action, migration 029) are being
-- replaced in the UI with one plain «توضیحات» box — five near-identical
-- free-text areas asking the responsible person to categorize their own
-- notes turned out to be more friction than value. This consolidates them
-- into a single description column, folding any existing content into it
-- (each non-empty field becomes one labeled paragraph, so nothing typed
-- so far is lost) before dropping the five old columns.

alter table case_updates add column if not exists description text;

comment on column case_updates.description is 'kind=''task'' rows only — free-text notes, replacing the five separate root_cause/corrective_action/preventive_action/latest_update/next_action fields. Editable by the task''s responsible person or admin, same as those were.';

update case_updates
set description = nullif(concat_ws(
    E'\n\n',
    case when nullif(trim(root_cause), '') is not null then 'علت ریشه‌ای: ' || trim(root_cause) end,
    case when nullif(trim(corrective_action), '') is not null then 'اقدام اصلاحی: ' || trim(corrective_action) end,
    case when nullif(trim(preventive_action), '') is not null then 'اقدام پیشگیرانه: ' || trim(preventive_action) end,
    case when nullif(trim(next_action), '') is not null then 'اقدام بعدی: ' || trim(next_action) end,
    nullif(trim(latest_update), '')
), '')
where kind = 'task';

alter table case_updates
    drop column if exists root_cause,
    drop column if exists corrective_action,
    drop column if exists preventive_action,
    drop column if exists next_action,
    drop column if exists latest_update;
