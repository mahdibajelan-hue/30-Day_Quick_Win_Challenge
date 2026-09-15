-- Tasks (case_updates, kind='task') used to require a case_id, which
-- meant a project with no اقدام زودبازده/میان‌مدت decided yet (or an
-- admin/تیم پشتیبانی کارفرما workflow that isn't tied to one) could never
-- have a task defined for it at all — reported as "ادمین نمی‌تواند روی
-- همه پروژه‌ها تسک تعریف کند، توی لیست انتخابی وجود ندارد": the project
-- itself was always selectable, but its case dropdown was empty, and
-- submission required a case. This makes case_id optional and gives
-- every task its own project_name directly, so a "تسک عمومی پروژه" with
-- no specific case can exist. A task that DOES have a case keeps
-- rolling up into that case's progress exactly as before — this is
-- purely additive.

alter table case_updates add column if not exists project_name text;

comment on column case_updates.project_name is 'Direct project reference for a task not tied to any case (case_id null) — a task WITH a case still gets this backfilled/kept in sync from cases.project_name, so every task row has it regardless.';

-- Backfill every existing row (progress entries included, harmless) from
-- its case.
update case_updates cu
set project_name = c.project_name
from cases c
where cu.case_id = c.id and cu.project_name is null;

alter table case_updates alter column case_id drop not null;

alter table case_updates add constraint case_updates_task_has_project
    check (kind <> 'task' or project_name is not null);

-- Re-point the two RLS policies that reached project_name by joining
-- through cases (migration 024) — they still work as-is for a task WITH a
-- case, but a caseless one (case_id null) can never satisfy `c.id =
-- case_updates.case_id`, so it needs its own additive read policy for
-- each, scoped by the new direct column instead.
create policy "scoped read on caseless case_updates" on case_updates
    for select using (
        case_id is null
        and exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = case_updates.project_name
        )
    );

create policy "guide project caseless case_updates visible to all" on case_updates
    for select using (
        case_id is null
        and exists (select 1 from projects p where p.name = case_updates.project_name and p.is_guide = true)
    );

-- Lock the new column the same way every other task-definition field is
-- already locked against a non-admin rewriting it through the "responsible
-- person can submit task for approval" update policy (migration 024) —
-- carrying forward every field migrations 028/029 already added to this
-- same lock list (start_date/severity/responsible_unit), plus project_name.
create or replace function case_updates_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.case_id := old.case_id;
        new.project_name := old.project_name;
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
