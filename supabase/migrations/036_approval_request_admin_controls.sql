-- Two corrections to the متن درخواست مصوبه permission model, both reported
-- straight after 034/178 shipped:
--
-- 1. There was no UPDATE policy at all on approval_requests (migration 032
--    deliberately left it that way, since every write besides the initial
--    insert was meant to go through sign_approval_request()) — but that
--    also means a plain typo in a submitted مصوبه could never be fixed,
--    and there was no way to delete one either even though an admin
--    DELETE policy already existed. Editing gets a real admin-only UPDATE
--    policy now, mirroring the existing "admin update on cases" pattern
--    used elsewhere in this schema; deleting already worked once the
--    frontend grew a button for it.
--
-- 2. Signing was restricted (migration 034) to only that project's real
--    کارفرما/مشاور/پیمانکار PM, removing admin's previous ability to sign
--    for any org — turns out that was wanted after all, so it's restored
--    here: admin can sign for any organization on any project again,
--    *in addition to* each org's own real PM still being able to sign
--    their own slot.

create policy "admin update on approval_requests" on approval_requests
    for update using (is_admin()) with check (is_admin());

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

    if not is_admin() and not exists (
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
