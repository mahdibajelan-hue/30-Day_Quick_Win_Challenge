-- Reported: "امکان ویرایش مسئول تسک با کاربر ادمین که خودم هستم وجود
-- نداره" — an admin could never set themselves as a task's «مسئول
-- پیگیری» (nor pick themselves when defining a new task), because
-- list_project_users(project_name) (migration 022) only returns people
-- who hold a user_project_access grant on that specific project — and an
-- admin, being globally scoped rather than tied to any one project,
-- normally has no such grant anywhere. The admin account simply never
-- appeared in the dropdown for any project.
--
-- Fix: union in every admin account too, labeled "ادمین سامانه" as its
-- organization, so any admin can always assign a task to themselves (to
-- log something they personally did, for example) on any project — same
-- access rule as the existing branch (caller must be admin or already
-- have a grant on that project). If an admin happens to ALSO hold a real
-- user_project_access grant on the same project, they show up twice
-- (once per organization) — a harmless cosmetic duplicate, not a
-- correctness issue, so not worth the extra complexity to de-duplicate.

create or replace function list_project_users(p_project_name text)
returns table (
    user_id uuid,
    email text,
    first_name text,
    last_name text,
    organization text
)
language sql
stable
security definer
set search_path = public
as $$
    select au.user_id, au.email, au.first_name, au.last_name, upa.organization
    from user_project_access upa
    join app_users au on au.user_id = upa.user_id
    where upa.project_name = p_project_name
      and (
        is_admin()
        or exists (
            select 1 from user_project_access mine
            where mine.user_id = auth.uid()
              and mine.project_name = p_project_name
        )
      )
    union
    select au.user_id, au.email, au.first_name, au.last_name, 'ادمین سامانه' as organization
    from app_users au
    where au.role = 'admin'
      and (
        is_admin()
        or exists (
            select 1 from user_project_access mine
            where mine.user_id = auth.uid()
              and mine.project_name = p_project_name
        )
      )
    order by first_name nulls last, last_name nulls last, email;
$$;

grant execute on function list_project_users(text) to authenticated;
