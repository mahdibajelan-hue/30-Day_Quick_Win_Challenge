-- ============================================================
-- Security fix: "responsible person can submit task for approval"
-- (migration 018) only restricts the RESULTING ROW via using/with
-- check on `status` + `responsible_email` — Postgres RLS has no
-- built-in way to restrict which OTHER columns an allowed UPDATE may
-- touch. Since the policy's using/with check never look at any column
-- besides status, a task's responsible person (an ordinary,
-- non-admin app_user — e.g. a پیمانکار/مشاور employee) can submit an
-- UPDATE that sets status correctly AND, in the very same call,
-- silently rewrite title, project_name, responsible_name,
-- responsible_email, or due_date to anything they want. Concretely,
-- from the browser console, on any task already assigned to them:
--
--   supabase.from('quick_win_tasks').update({
--     status: 'در انتظار تایید',
--     title: '<img src=x onerror=...>',   -- stored HTML injection, later
--                                          -- emailed verbatim by
--                                          -- notify-overdue-tasks
--     project_name: 'some other project', -- bypasses user_project_access
--                                          -- scoping entirely for this row
--     due_date: '2999-01-01',             -- evades the overdue/
--                                          -- accountability system
--   }).eq('id', <their own task id>)
--
-- Verified locally (dry run): status/title/project_name/due_date all
-- change under the pre-fix policy. responsible_email happens to be
-- self-defending here — changing it in the same call makes the
-- existing with check's own exists(...) fail, since it re-evaluates
-- ownership against the NEW row — but that's an accident of this
-- policy's exact shape, not a real restriction on the column, so it's
-- locked below too as defense-in-depth against the policy changing later.
--
-- This is the exact same class of bug migration 010 already fixed for
-- app_users (a non-admin self-promoting to role='admin' through the
-- "update their own profile" policy) with a BEFORE UPDATE trigger —
-- applying the identical pattern here.
-- ============================================================

create or replace function quick_win_tasks_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.project_name := old.project_name;
        new.title := old.title;
        new.responsible_name := old.responsible_name;
        new.responsible_email := old.responsible_email;
        new.due_date := old.due_date;
        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.completed_at := old.completed_at;
        new.overdue_notified_at := old.overdue_notified_at;
    end if;
    return new;
end;
$$;

drop trigger if exists quick_win_tasks_lock_privileged_fields on quick_win_tasks;
create trigger quick_win_tasks_lock_privileged_fields
    before update on quick_win_tasks
    for each row
    execute function quick_win_tasks_lock_privileged_fields();
