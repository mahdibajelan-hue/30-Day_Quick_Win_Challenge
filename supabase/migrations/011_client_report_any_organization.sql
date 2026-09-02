-- ============================================================
-- Migration: let a manager of ANY organization (not just کارفرما)
-- submit «اطلاعات پایه پروژه» (client_reports / "Form 1").
--
-- This form and its INSERT policy were originally کارفرما-only (see
-- migration 002's comment), which is why مشاور/پیمانکار managers never
-- saw it in the nav and could not submit it even if they had. Per
-- explicit product decision, this is now open to every organization —
-- widen the INSERT check to match the existing SELECT policy's scope
-- (any user_project_access row for that project, regardless of
-- organization) instead of requiring organization = 'کارفرما'.
-- ============================================================

drop policy if exists "client managers can insert own project client_reports" on client_reports;
create policy "managers can insert own project client_reports" on client_reports
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = client_reports.project_name
        )
    );
