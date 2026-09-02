-- ============================================================
-- Migration: let a user complete their own personal-info profile
-- (first/last name, phone, company, job title) from a "پروفایل من"
-- form, alongside the existing password-change flow.
-- ============================================================

alter table app_users
    add column if not exists first_name text,
    add column if not exists last_name text,
    add column if not exists phone text,
    add column if not exists company_name text,
    add column if not exists job_title text;

-- A user may update their own row (needed for the profile form to save
-- at all — no self-UPDATE policy on app_users existed before this,
-- only the self-INSERT one added in migration 008). Scoped to
-- ownership only; the trigger below is what actually restricts which
-- columns a non-admin update may change.
create policy "users can update their own profile" on app_users
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- This UPDATE policy is deliberately row-scoped only (auth.uid() =
-- user_id), not column-scoped, because Postgres RLS can't restrict
-- individual columns on its own. Without this trigger, a non-admin
-- could use the exact same client-side call the profile form makes to
-- also overwrite their own role to 'admin', reassign user_id to
-- someone else's row, or desync email from what Supabase Auth
-- actually has on file. Locks those three fields back to their
-- existing value for anyone who isn't already an admin.
create or replace function app_users_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.role := old.role;
        new.user_id := old.user_id;
        new.email := old.email;
    end if;
    return new;
end;
$$;

create trigger app_users_lock_privileged_fields
    before update on app_users
    for each row
    execute function app_users_lock_privileged_fields();
