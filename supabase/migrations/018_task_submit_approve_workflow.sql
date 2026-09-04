-- ============================================================
-- Migration: a Quick Win task no longer jumps straight from open to
-- done. The responsible person now *submits* their completed work
-- («در انتظار تایید» — pending admin approval), and only an admin's
-- final approval moves it to «انجام‌شده». Admin can also send a
-- submission back for rework, which returns it to «در حال انجام».
--
-- submitted_at / submitted_note record what the responsible person
-- reported when they submitted. completed_at (already existed) keeps
-- meaning exactly what it did before: when the task actually became
-- «انجام‌شده», i.e. admin's final approval.
-- ============================================================

alter table quick_win_tasks add column if not exists submitted_at timestamptz;
alter table quick_win_tasks add column if not exists submitted_note text;

alter table quick_win_tasks drop constraint if exists quick_win_tasks_status_check;
alter table quick_win_tasks add constraint quick_win_tasks_status_check
    check (status in ('باز', 'در حال انجام', 'در انتظار تایید', 'انجام‌شده'));

-- Lets a task's own responsible person move it into the pending-approval
-- state themselves — nothing more. They still can't set status to
-- «انجام‌شده» directly (with check pins the result to «در انتظار تایید»),
-- and can't resubmit a task admin already finished (using excludes
-- «انجام‌شده»). This is purely additive alongside the existing admin
-- `for all` and scoped-read policies — Postgres OR's permissive policies
-- together, so it can only ever add this one narrow capability.
drop policy if exists "responsible person can submit task for approval" on quick_win_tasks;
create policy "responsible person can submit task for approval" on quick_win_tasks
    for update
    using (
        status <> 'انجام‌شده'
        and exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.email = quick_win_tasks.responsible_email
        )
    )
    with check (
        status = 'در انتظار تایید'
        and exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.email = quick_win_tasks.responsible_email
        )
    );
