-- ============================================================
-- «در خروجی کلیدی و معیار عبور امکان ضمیمه نمودن فایل هم وجود داشته
-- باشد» — project_phase_items.evidence was always just a free-text
-- field ("لینک یا توضیح"), never an actual uploaded file. This adds a
-- real file attachment, mirroring the exact same Storage pattern
-- already used for signature uploads (migration 034): a public bucket,
-- write scoped by folder ownership — here the folder is the project
-- name, checked against user_project_access the same way every other
-- per-project write in this module already is.
--
-- Path convention: <project_name>/<phase_code>/<kind>/<item_id>/<file>
-- ============================================================

alter table project_phase_items add column if not exists evidence_file_url text;
comment on column project_phase_items.evidence_file_url is 'Public URL of an uploaded evidence file ("lifecycle-evidence" Storage bucket, path <project_name>/<phase_code>/<kind>/<item_id>/<file>), alongside the existing free-text evidence field.';

insert into storage.buckets (id, name, public)
values ('lifecycle-evidence', 'lifecycle-evidence', true)
on conflict (id) do nothing;

create policy "project member can upload lifecycle evidence" on storage.objects
    for insert with check (
        bucket_id = 'lifecycle-evidence' and (
            is_admin() or exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid() and upa.project_name = (storage.foldername(name))[1]
            )
        )
    );

create policy "project member can replace lifecycle evidence" on storage.objects
    for update using (
        bucket_id = 'lifecycle-evidence' and (
            is_admin() or exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid() and upa.project_name = (storage.foldername(name))[1]
            )
        )
    );

create policy "project member can delete lifecycle evidence" on storage.objects
    for delete using (
        bucket_id = 'lifecycle-evidence' and (
            is_admin() or exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid() and upa.project_name = (storage.foldername(name))[1]
            )
        )
    );

create policy "lifecycle evidence is publicly readable" on storage.objects
    for select using (bucket_id = 'lifecycle-evidence');
