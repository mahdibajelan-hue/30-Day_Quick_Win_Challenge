-- ============================================================
-- Project Lifecycle & Stage-Gate module.
--
-- Implements the company's official 9-gate project lifecycle model
-- (مدل چرخه عمر پروژه‌های شرکت مهندسی و توسعه گاز ایران, Rev.01,
-- 1405-06-17) as configurable master data plus per-project tracking:
--
--   lifecycle_phases        — the 9 official phases (G1..G9), one
--                              organization-wide template (there is
--                              only ever one official lifecycle here,
--                              so this is NOT multi-tenant per project)
--   lifecycle_objectives / lifecycle_outputs / lifecycle_criteria
--                              — the master checklist items under each
--                                phase ("اهداف مرحله" / "خروجی کلیدی" /
--                                "معیار عبور" from the reference image)
--   project_lifecycle_phases  — one row per project per phase: weight,
--                              planned/actual dates, the Basic-Design
--                              engine's manual actual %, and gate status
--   project_phase_items       — one row per project per master item:
--                              completion/verification state, evidence,
--                              owner — this is what actually drives
--                              progress, never a typed-in percentage
--   lifecycle_gate_decisions  — PASS / CONDITIONAL PASS / RETURN records
--   lifecycle_progress_history — immutable log of Basic Design's
--                              periodic actual-% updates (EPC's own
--                              E/P/C trend already lives in
--                              client_reports' history, reused as-is)
--   lifecycle_audit_log        — weight/config changes, for traceability
--
-- G6 (اجرای پروژه / EPC) deliberately has NO new E/P/C table: this app
-- already tracks per-project Engineering/Procurement/Construction
-- planned+actual progress and each discipline's weight on
-- client_reports (migrations 025 و 030) — the lifecycle module reads
-- the project's latest client_reports row for G6 instead of duplicating
-- that data.
--
-- "Steps" from the module's design brief are deliberately not a
-- separate table: for every step-engine phase (G1,G2,G3,G5,G7,G8,G9)
-- the phase's own Objectives already serve as its step checklist — the
-- reference image only ever shows three bullet categories per phase
-- (اهداف / خروجی کلیدی / معیار عبور), so a fourth parallel category
-- would just duplicate Objectives without adding real content.
-- ============================================================

-- ============================================================
-- 1. lifecycle_phases — the 9 official gates (master data)
-- ============================================================
create table lifecycle_phases (
    code text primary key,                          -- 'G1'..'G9'
    sort_order int not null,
    phase_group text not null
        check (phase_group in ('fel', 'execution', 'commissioning')),
    title text not null,
    responsible text not null,
    gate_name text not null,
    gate_threshold_pct numeric not null check (gate_threshold_pct between 0 and 100),
    progress_engine text not null
        check (progress_engine in ('step', 'basic_design', 'epc')),
    icon_key text not null default 'target',
    objectives_weight_pct numeric not null default 50 check (objectives_weight_pct >= 0),
    outputs_weight_pct numeric not null default 30 check (outputs_weight_pct >= 0),
    criteria_weight_pct numeric not null default 20 check (criteria_weight_pct >= 0),
    is_active boolean not null default true,
    updated_at timestamptz not null default now(),
    constraint lifecycle_phases_category_weights_sum check (
        objectives_weight_pct + outputs_weight_pct + criteria_weight_pct = 100
    )
);

comment on table lifecycle_phases is 'The one official 9-gate lifecycle template (G1..G9) — organization-wide master data, not per-project.';
comment on column lifecycle_phases.progress_engine is 'step = checklist-driven (Engine A); basic_design/epc = value-weighted, periodically updated (Engine B).';

-- ============================================================
-- 2. Master checklist items per phase
-- ============================================================
create table lifecycle_objectives (
    id bigint generated always as identity primary key,
    phase_code text not null references lifecycle_phases(code) on delete cascade,
    seq int not null default 0,
    title text not null,
    description text,
    weight numeric check (weight is null or weight >= 0),
    is_active boolean not null default true
);
create index lifecycle_objectives_phase_idx on lifecycle_objectives (phase_code);

create table lifecycle_outputs (
    id bigint generated always as identity primary key,
    phase_code text not null references lifecycle_phases(code) on delete cascade,
    seq int not null default 0,
    title text not null,
    description text,
    weight numeric check (weight is null or weight >= 0),
    is_active boolean not null default true
);
create index lifecycle_outputs_phase_idx on lifecycle_outputs (phase_code);

create table lifecycle_criteria (
    id bigint generated always as identity primary key,
    phase_code text not null references lifecycle_phases(code) on delete cascade,
    seq int not null default 0,
    title text not null,
    description text,
    weight numeric check (weight is null or weight >= 0),
    is_mandatory boolean not null default true,
    is_active boolean not null default true
);
create index lifecycle_criteria_phase_idx on lifecycle_criteria (phase_code);

comment on column lifecycle_objectives.weight is 'Null = split equally with the other active objectives of the same phase at read time.';

-- ============================================================
-- 3. project_lifecycle_phases — per-project phase instance
-- ============================================================
create table project_lifecycle_phases (
    id bigint generated always as identity primary key,
    project_name text not null,
    phase_code text not null references lifecycle_phases(code),
    weight_pct numeric check (weight_pct is null or weight_pct >= 0),
    planned_start date,
    planned_finish date,
    actual_start date,
    actual_finish date,
    contract_value numeric,                 -- Basic Design only
    manual_actual_pct numeric check (manual_actual_pct is null or manual_actual_pct between 0 and 100),
    gate_status text not null default 'not_ready'
        check (gate_status in ('not_ready', 'ready_for_review', 'conditional', 'passed', 'blocked')),
    gate_requested_at timestamptz,
    gate_requested_by text,
    updated_at timestamptz not null default now(),
    updated_by text,
    unique (project_name, phase_code),
    constraint plp_finish_after_start check (
        (planned_finish is null or planned_start is null or planned_finish >= planned_start)
        and (actual_finish is null or actual_start is null or actual_finish >= actual_start)
    )
);
create index project_lifecycle_phases_project_idx on project_lifecycle_phases (project_name);

comment on column project_lifecycle_phases.manual_actual_pct is 'Latest approved actual % for the basic_design engine — set only via a lifecycle_progress_history entry, never edited free-form.';

-- ============================================================
-- 4. project_phase_items — actionable objective/output/criterion state
-- ============================================================
-- item_id points at lifecycle_objectives/outputs/criteria depending on
-- `kind`; a single polymorphic FK isn't expressible in plain SQL, so it
-- is left unenforced here and validated by the frontend (same tradeoff
-- case_updates already makes with its own kind-discriminated columns).
create table project_phase_items (
    id bigint generated always as identity primary key,
    project_name text not null,
    phase_code text not null references lifecycle_phases(code),
    kind text not null check (kind in ('objective', 'output', 'criterion')),
    item_id bigint not null,
    status text not null default 'pending'
        check (status in (
            'not_started', 'in_progress', 'completed', 'blocked',
            'pending', 'submitted', 'verified', 'rejected', 'failed', 'waived'
        )),
    owner text,
    due_date date,
    completion_date date,
    evidence text,
    comment text,
    submitted_by text,
    verified_by text,
    verification_date date,
    updated_at timestamptz not null default now(),
    updated_by text,
    unique (project_name, phase_code, kind, item_id)
);
create index project_phase_items_project_phase_idx on project_phase_items (project_name, phase_code);

comment on table project_phase_items is 'Per-project completion state of one master objective/output/criterion. Progress is always derived from these rows — never typed in directly.';

-- ============================================================
-- 5. Gate decisions
-- ============================================================
create table lifecycle_gate_decisions (
    id bigint generated always as identity primary key,
    project_name text not null,
    phase_code text not null references lifecycle_phases(code),
    decision text not null check (decision in ('pass', 'conditional', 'return')),
    reason text,                 -- return
    condition_text text,         -- conditional
    condition_owner text,        -- conditional
    condition_due_date date,     -- conditional
    decided_by text not null,
    decided_at timestamptz not null default now()
);
create index lifecycle_gate_decisions_project_phase_idx on lifecycle_gate_decisions (project_name, phase_code);

-- ============================================================
-- 6. Basic Design periodic progress history
-- ============================================================
create table lifecycle_progress_history (
    id bigint generated always as identity primary key,
    project_name text not null,
    phase_code text not null references lifecycle_phases(code),
    period_label text,
    previous_pct numeric,
    new_pct numeric not null check (new_pct between 0 and 100),
    comment text,
    recorded_by text not null,
    recorded_at timestamptz not null default now()
);
create index lifecycle_progress_history_project_phase_idx on lifecycle_progress_history (project_name, phase_code, recorded_at);

-- ============================================================
-- 7. Audit log (weight changes, phase-date changes, config edits)
-- ============================================================
create table lifecycle_audit_log (
    id bigint generated always as identity primary key,
    project_name text,
    phase_code text,
    action text not null,
    field text,
    old_value text,
    new_value text,
    changed_by text not null,
    changed_at timestamptz not null default now()
);
create index lifecycle_audit_log_project_idx on lifecycle_audit_log (project_name, changed_at);

-- ============================================================
-- 8. RLS
-- ============================================================
alter table lifecycle_phases enable row level security;
alter table lifecycle_objectives enable row level security;
alter table lifecycle_outputs enable row level security;
alter table lifecycle_criteria enable row level security;
alter table project_lifecycle_phases enable row level security;
alter table project_phase_items enable row level security;
alter table lifecycle_gate_decisions enable row level security;
alter table lifecycle_progress_history enable row level security;
alter table lifecycle_audit_log enable row level security;

-- Master data: readable by every authenticated manager (they need it to
-- render the orbit for their own project); writable by PMO/admin only.
create policy "authenticated read lifecycle_phases" on lifecycle_phases
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_phases" on lifecycle_phases
    for all using (is_admin()) with check (is_admin());

create policy "authenticated read lifecycle_objectives" on lifecycle_objectives
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_objectives" on lifecycle_objectives
    for all using (is_admin()) with check (is_admin());

create policy "authenticated read lifecycle_outputs" on lifecycle_outputs
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_outputs" on lifecycle_outputs
    for all using (is_admin()) with check (is_admin());

create policy "authenticated read lifecycle_criteria" on lifecycle_criteria
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_criteria" on lifecycle_criteria
    for all using (is_admin()) with check (is_admin());

-- Per-project data: same scoping shape as client_reports — admin, or any
-- manager with access to the project (any organization, since phase
-- ownership here isn't organization-specific the way check_ins is).
create policy "admin full access on project_lifecycle_phases" on project_lifecycle_phases
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on project_lifecycle_phases" on project_lifecycle_phases
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_lifecycle_phases.project_name
        )
        or exists (select 1 from projects where projects.name = project_lifecycle_phases.project_name and projects.is_guide = true)
    );
create policy "manager write own project on project_lifecycle_phases" on project_lifecycle_phases
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_lifecycle_phases.project_name
        )
    );
create policy "manager update own project on project_lifecycle_phases" on project_lifecycle_phases
    for update using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_lifecycle_phases.project_name
        )
    );

create policy "admin full access on project_phase_items" on project_phase_items
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on project_phase_items" on project_phase_items
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_phase_items.project_name
        )
        or exists (select 1 from projects where projects.name = project_phase_items.project_name and projects.is_guide = true)
    );
create policy "manager write own project on project_phase_items" on project_phase_items
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_phase_items.project_name
        )
    );
create policy "manager update own project on project_phase_items" on project_phase_items
    for update using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_phase_items.project_name
        )
    );

-- Gate PASS / CONDITIONAL / RETURN decisions are an Approver/PMO action —
-- admin-only, matching how evaluating/deciding a Quick Win is admin-only.
create policy "admin full access on lifecycle_gate_decisions" on lifecycle_gate_decisions
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_gate_decisions" on lifecycle_gate_decisions
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_gate_decisions.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_gate_decisions.project_name and projects.is_guide = true)
    );

create policy "admin full access on lifecycle_progress_history" on lifecycle_progress_history
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_progress_history" on lifecycle_progress_history
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_progress_history.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_progress_history.project_name and projects.is_guide = true)
    );
create policy "manager insert own project on lifecycle_progress_history" on lifecycle_progress_history
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_progress_history.project_name
        )
    );

create policy "admin full access on lifecycle_audit_log" on lifecycle_audit_log
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_audit_log" on lifecycle_audit_log
    for select using (
        is_admin() or (
            project_name is not null and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid() and upa.project_name = lifecycle_audit_log.project_name
            )
        )
    );
create policy "manager insert own project on lifecycle_audit_log" on lifecycle_audit_log
    for insert with check (
        is_admin() or (
            project_name is not null and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid() and upa.project_name = lifecycle_audit_log.project_name
            )
        )
    );
