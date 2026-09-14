-- Digital signature IMAGES for متن درخواست مصوبه — uploaded once in
-- مشخصات من (Storage), then stamped into a request's signed_by_* column
-- at the moment of signing, so a signature already on a request keeps
-- looking exactly as it did when signed even if the person later
-- replaces their uploaded image.

alter table app_users add column if not exists signature_url text;

comment on column app_users.signature_url is 'Public URL of this user''s uploaded signature image ("signatures" Storage bucket, path <user_id>/signature.<ext>) — snapshotted into an approval_requests signed_by_* slot by sign_approval_request() at signing time.';

insert into storage.buckets (id, name, public)
values ('signatures', 'signatures', true)
on conflict (id) do nothing;

-- Path convention is <user_id>/signature.<ext> — storage.foldername(name)
-- splits the object path into segments, so [1] is that leading user_id
-- folder. Each user may only write inside their own folder; the bucket is
-- public for read (signatures need to render inside a request that every
-- project member, and eventually the CEO's office, can view/print).
create policy "signature owner can upload" on storage.objects
    for insert with check (
        bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "signature owner can update" on storage.objects
    for update using (
        bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "signature owner can delete" on storage.objects
    for delete using (
        bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "signatures are publicly readable" on storage.objects
    for select using (bucket_id = 'signatures');

-- Re-create sign_approval_request (migration 032) for two changes:
--  1. Snapshot the signer's signature_url into the recorded signature.
--  2. Drop the is_admin() bypass on the permission check — «فقط مدیران
--     پروژه مشاور و پیمانکار و کارفرمای همان پروژه اجازه امضا داشته
--     باشند»: signing is now restricted to that project's real org PM,
--     full stop, matching the same restriction now enforced in the
--     frontend's arSignatureSectionHtml (canSign). Enforcing it here too
--     (not just hiding the button) is what actually makes it a rule
--     rather than a suggestion.
create or replace function sign_approval_request(p_request_id bigint, p_organization text)
returns approval_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    v_request approval_requests;
    v_name text;
    v_email text;
    v_signature_url text;
    v_column text;
begin
    if p_organization not in ('کارفرما', 'مشاور', 'پیمانکار') then
        raise exception 'سازمان نامعتبر است';
    end if;

    select * into v_request from approval_requests where id = p_request_id;
    if v_request is null then
        raise exception 'درخواست مصوبه یافت نشد';
    end if;

    if not exists (
        select 1 from user_project_access upa
        where upa.user_id = auth.uid()
          and upa.project_name = v_request.project_name
          and upa.organization = p_organization
    ) then
        raise exception 'شما دسترسی امضا برای این سازمان در این پروژه را ندارید';
    end if;

    select email, coalesce(nullif(trim(concat(first_name, ' ', last_name)), ''), email), signature_url
        into v_email, v_name, v_signature_url
        from app_users where user_id = auth.uid();

    v_column := case p_organization
        when 'کارفرما' then 'signed_by_client'
        when 'مشاور' then 'signed_by_consultant'
        when 'پیمانکار' then 'signed_by_contractor'
    end;

    execute format('update approval_requests set %I = $1 where id = $2', v_column)
        using jsonb_build_object('name', v_name, 'email', v_email, 'signed_at', now(), 'signature_url', v_signature_url), p_request_id;

    select * into v_request from approval_requests where id = p_request_id;
    return v_request;
end;
$$;

grant execute on function sign_approval_request(bigint, text) to authenticated;
