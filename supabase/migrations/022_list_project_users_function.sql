-- Redesign backlog (P0): "مسئول/PM از فهرست کاربران، نه تایپ آزاد".
--
-- Today, every "responsible person" field on check_ins (plan_responsible) and
-- client_reports (client_pm_name/contractor_pm_name/consultant_pm_name) is a
-- free-text <input>, never checked against app_users — the exact duplication
-- the redesign report flags under "هویت مسئول/PM" (section C). To replace
-- those inputs with a <select> populated from the real people who have
-- access to the project, the frontend needs a way to list them.
--
-- It can't just query user_project_access/app_users directly: a manager's
-- own RLS on both tables only ever returns their OWN row (see "self read own
-- project access" on user_project_access, and the admin-only/self-only
-- policies on app_users) — by design, a manager can't see who else has
-- access to anything. Rather than widen either table's RLS (which would let
-- any manager start reading teammate rows in general, well beyond what this
-- feature needs), this is a single SECURITY DEFINER function that returns
-- only {user_id, email, name, organization} for people who share the
-- specific project the caller is already asking about, and only if the
-- caller is admin or themselves has a grant on that same project.
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
    order by au.first_name nulls last, au.last_name nulls last, au.email;
$$;

grant execute on function list_project_users(text) to authenticated;
