-- ============================================================
-- «اگر برنامه زمانبندی مطلوبی کاربران درست کردند ... بشه اونو به عنوان
-- یک نمونه موفق ذخیره کرد و یک نام مناسب هم بهش داد» — lets a manager
-- snapshot a project's current schedule (whatever Execution Strategy
-- it ended up on, plus every phase's real planned window and its own
-- schedule-item tree) as a named, reusable "success story" once they
-- judge it good/realistic — organization-wide, like every other master
-- data table in this module, so it can inform future projects.
--
-- Everything here is captured RELATIVE (day offsets, durations), never
-- as absolute dates, since the whole point is reuse on a future
-- project with its own start date. source_item_id/source_parent_id
-- keep the original schedule_items tree shape (same reasoning as
-- lifecycle_schedule_baseline_items in migration 039: a frozen
-- snapshot must survive the live rows it was taken from later being
-- edited or deleted).
-- ============================================================

create table lifecycle_schedule_success_templates (
    id bigint generated always as identity primary key,
    name text not null,
    source_project_name text not null,
    execution_strategy text,
    total_duration_days int,
    notes text,
    created_by text not null,
    created_at timestamptz not null default now()
);
create index lifecycle_schedule_success_templates_created_idx on lifecycle_schedule_success_templates (created_at);

create table lifecycle_schedule_success_template_phases (
    id bigint generated always as identity primary key,
    template_id bigint not null references lifecycle_schedule_success_templates(id) on delete cascade,
    phase_code text not null,
    day_offset_start int not null,
    duration_days int not null,
    seq int not null
);
create index lifecycle_schedule_success_template_phases_template_idx on lifecycle_schedule_success_template_phases (template_id);

create table lifecycle_schedule_success_template_items (
    id bigint generated always as identity primary key,
    template_id bigint not null references lifecycle_schedule_success_templates(id) on delete cascade,
    phase_code text not null,
    source_item_id bigint not null,
    source_parent_id bigint,
    title text not null,
    day_offset_from_phase_start int not null,
    duration_days int not null,
    weight_pct numeric,
    seq int not null
);
create index lifecycle_schedule_success_template_items_template_idx on lifecycle_schedule_success_template_items (template_id);

comment on table lifecycle_schedule_success_templates is 'A named snapshot of a project schedule a manager judged worth reusing — organization-wide library, read by every authenticated manager, written only by someone with access to the source project.';

-- ============================================================
-- RLS — read like any other master/reference data (every authenticated
-- manager needs to browse the library); insert restricted to someone
-- with access to the project actually being snapshotted, same shape as
-- lifecycle_schedule_baselines. No update policy anywhere (immutable
-- snapshot, same reasoning as migration 039); admin can delete a
-- mistaken one.
-- ============================================================
alter table lifecycle_schedule_success_templates enable row level security;
alter table lifecycle_schedule_success_template_phases enable row level security;
alter table lifecycle_schedule_success_template_items enable row level security;

create policy "authenticated read lifecycle_schedule_success_templates" on lifecycle_schedule_success_templates
    for select using (auth.uid() is not null);
create policy "admin delete lifecycle_schedule_success_templates" on lifecycle_schedule_success_templates
    for delete using (is_admin());
create policy "project member insert lifecycle_schedule_success_templates" on lifecycle_schedule_success_templates
    for insert with check (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_success_templates.source_project_name
        )
    );

create policy "authenticated read lifecycle_schedule_success_template_phases" on lifecycle_schedule_success_template_phases
    for select using (auth.uid() is not null);
create policy "admin delete lifecycle_schedule_success_template_phases" on lifecycle_schedule_success_template_phases
    for delete using (is_admin());
create policy "project member insert lifecycle_schedule_success_template_phases" on lifecycle_schedule_success_template_phases
    for insert with check (
        exists (
            select 1 from lifecycle_schedule_success_templates t
            join user_project_access upa on upa.project_name = t.source_project_name
            where t.id = lifecycle_schedule_success_template_phases.template_id and upa.user_id = auth.uid()
        ) or is_admin()
    );

create policy "authenticated read lifecycle_schedule_success_template_items" on lifecycle_schedule_success_template_items
    for select using (auth.uid() is not null);
create policy "admin delete lifecycle_schedule_success_template_items" on lifecycle_schedule_success_template_items
    for delete using (is_admin());
create policy "project member insert lifecycle_schedule_success_template_items" on lifecycle_schedule_success_template_items
    for insert with check (
        exists (
            select 1 from lifecycle_schedule_success_templates t
            join user_project_access upa on upa.project_name = t.source_project_name
            where t.id = lifecycle_schedule_success_template_items.template_id and upa.user_id = auth.uid()
        ) or is_admin()
    );
