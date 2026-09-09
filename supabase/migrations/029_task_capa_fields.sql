-- The "Issue Control Tower" dashboard originally shipped in this session as
-- a brand-new issues/issue_updates table pair, but that duplicated the
-- execution-task tracking that already exists as case_updates (kind='task')
-- — a mistaken requirement caught before it was ever applied anywhere. This
-- migration replaces that (deleted, never-applied) 029_issue_management.sql
-- with the right-sized change: extend the EXISTING task rows with the
-- richer fields the new dashboard needs (severity/unit for triage and
-- charts, CAPA/update fields for the responsible person to document their
-- own investigation), instead of a second, parallel entity.

alter table case_updates add column if not exists severity text
    check (severity in ('بحرانی', 'زیاد', 'متوسط', 'کم'));
alter table case_updates add column if not exists responsible_unit text;
alter table case_updates add column if not exists root_cause text;
alter table case_updates add column if not exists corrective_action text;
alter table case_updates add column if not exists preventive_action text;
alter table case_updates add column if not exists next_action text;
alter table case_updates add column if not exists latest_update text;

comment on column case_updates.severity is 'kind=''task'' rows only — admin-set triage severity, drives Task Control Tower KPIs/charts.';
comment on column case_updates.responsible_unit is 'kind=''task'' rows only — EPC functional unit responsible, admin-set.';
comment on column case_updates.root_cause is 'kind=''task'' rows only — settable by the task''s responsible person (like submitted_note already is), not just admin.';
comment on column case_updates.corrective_action is 'kind=''task'' rows only.';
comment on column case_updates.preventive_action is 'kind=''task'' rows only.';
comment on column case_updates.next_action is 'kind=''task'' rows only.';
comment on column case_updates.latest_update is 'kind=''task'' rows only — free-text running note; an "escalate" action also logs into this field as a prefixed line rather than needing a separate table.';

-- Re-lock the same way every prior task-field addition has (migrations
-- 020/028): the responsible-person "submit for approval" UPDATE policy's
-- using/with check only constrain task_status — without repeating this
-- pattern here, that same UPDATE could silently also rewrite severity or
-- responsible_unit, which are meant to stay admin-only triage/assignment
-- decisions. root_cause/corrective_action/preventive_action/next_action/
-- latest_update are deliberately left OFF this lock list: the entire point
-- of adding them is to let the responsible person document their own
-- investigation, the same way they already can via submitted_note.
create or replace function case_updates_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.case_id := old.case_id;
        new.kind := old.kind;
        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.status := old.status;
        new.progress_percent := old.progress_percent;
        new.note := old.note;
        new.reported_by := old.reported_by;
        new.title := old.title;
        new.responsible_name := old.responsible_name;
        new.responsible_email := old.responsible_email;
        new.start_date := old.start_date;
        new.due_date := old.due_date;
        new.completed_at := old.completed_at;
        new.overdue_notified_at := old.overdue_notified_at;
        new.severity := old.severity;
        new.responsible_unit := old.responsible_unit;
    end if;
    return new;
end;
$$;

drop trigger if exists case_updates_lock_privileged_fields on case_updates;
create trigger case_updates_lock_privileged_fields
    before update on case_updates
    for each row
    execute function case_updates_lock_privileged_fields();
