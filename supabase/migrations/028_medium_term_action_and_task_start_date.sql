-- Two additions to support "تبدیل به اقدام میان‌مدت" as a real, trackable
-- outcome of evaluating a Quick Win proposal (not just a decision label with
-- no effect), and letting execution tasks carry a start date, not just a
-- due date.

-- 1. New case status: اقدام میان‌مدت -------------------------------------
-- A proposal converted to a medium-term action is NOT the project's selected
-- Quick Win (DECIDED_STATUSES / the "only one selected per project" exclusivity
-- stays scoped to انتخاب‌شده/در حال اجرا/بسته‌شده, unchanged) — several
-- proposals across different orgs can independently become اقدام میان‌مدت at
-- once. It still needs to become project-wide visible (not just to the
-- proposing org) once decided, same as an already-selected Quick Win, so the
-- تسک تعریف‌کردن (task tracking) flow on it works for every project member.

alter table cases drop constraint if exists cases_status_check;
alter table cases add constraint cases_status_check
    check (status in ('پیشنهاد', 'ارزیابی‌شده', 'انتخاب‌شده', 'در حال اجرا', 'بسته‌شده', 'اقدام میان‌مدت'));

drop policy if exists "scoped read on cases" on cases;
create policy "scoped read on cases" on cases
    for select using (
        is_admin()
        or (
            status in ('پیشنهاد', 'ارزیابی‌شده')
            and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid()
                  and upa.project_name = cases.project_name
                  and upa.organization = cases.organization
            )
        )
        or (
            status in ('انتخاب‌شده', 'در حال اجرا', 'بسته‌شده', 'اقدام میان‌مدت')
            and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid()
                  and upa.project_name = cases.project_name
            )
        )
    );

-- 2. Task start date --------------------------------------------------------
-- Tasks under a case (case_updates, kind='task') so far only carried a
-- due_date; اجرای اقدامات زودبازده/میان‌مدت now also wants a start date.

alter table case_updates add column if not exists start_date date;

comment on column case_updates.start_date is 'Task start date (kind=''task'' rows only) — alongside the existing due_date.';

-- Re-lock the new column the same way every other task-definition field is
-- already locked against a non-admin rewriting it through the "responsible
-- person can submit task for approval" update policy (migration 024) — that
-- policy's using/with check only constrain task_status on the matched row,
-- so without this the same UPDATE could silently also rewrite start_date.
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
    end if;
    return new;
end;
$$;
