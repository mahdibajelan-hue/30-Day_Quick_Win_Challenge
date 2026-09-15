-- ============================================================
-- Demo data for the Project Lifecycle & Stage-Gate module — NOT a
-- migration; run manually in the Supabase SQL Editor AFTER both
-- 033_lifecycle_stage_gate.sql and seed_lifecycle_master_data.sql have
-- been applied. Mirrors seed_demo_project.sql's own conventions (a
-- "(نمونه آزمایشی)" project, attributed to the first admin found).
--
-- Demo project: «پروژه احداث ایستگاه رسیور گاز کیلومتر ۵۳ خط پنجم
-- سراسری» — currently mid-EPC (G6), which is exactly the scenario the
-- module's Executive View is designed to show at a glance:
--   Overall Actual  ≈ 63%     Overall Planned ≈ 68%     Variance ≈ -5%
--   Basic Design (G4): weight 12%, actual 95% — already gate-PASSED
--   EPC (G6): weight 55%, E 15%/82%, P 35%/64%, C 50%/37% (from
--             client_reports, reused rather than duplicated)
-- G6's own Objectives/Outputs are partially done but its mandatory
-- Exit Criteria are still pending — deliberately, so opening this
-- demo project immediately demonstrates the module's central rule:
-- high progress does not by itself mean the gate is passed.
--
-- Safe to re-run: it clears any previous rows for this project name
-- from all 5 lifecycle project tables (plus its client_reports row)
-- before reinserting.
-- ============================================================

do $$
declare
    v_project text := 'پروژه احداث ایستگاه رسیور گاز کیلومتر ۵۳ خط پنجم سراسری (نمونه آزمایشی)';
    v_user_id uuid;
    v_email text;
begin
    select user_id, email into v_user_id, v_email from app_users where role = 'admin' limit 1;
    if v_user_id is null then
        raise exception 'No admin found in app_users — set up an admin first, then re-run this script.';
    end if;

    -- 0. Clean slate for a re-run
    delete from lifecycle_gate_decisions where project_name = v_project;
    delete from lifecycle_progress_history where project_name = v_project;
    delete from lifecycle_audit_log where project_name = v_project;
    delete from project_phase_items where project_name = v_project;
    delete from project_lifecycle_phases where project_name = v_project;
    delete from client_reports where project_name = v_project;

    -- 1. Project
    insert into projects (name)
    select v_project
    where not exists (select 1 from projects where name = v_project);

    -- 2. اطلاعات پایه پروژه — overall + E/P/C planned/actual/weight
    -- (this is the module's one source of truth for G6's EPC numbers)
    insert into client_reports (
        user_id, project_name, plan_name, contract_type,
        contract_start_date, contract_end_date, forecast_completion_date,
        progress_planned, progress_physical,
        progress_engineering_planned, progress_engineering,
        progress_procurement_planned, progress_procurement,
        progress_construction_planned, progress_construction,
        progress_engineering_weight, progress_procurement_weight, progress_construction_weight
    ) values (
        v_user_id, v_project, 'احداث ایستگاه رسیور گاز کیلومتر ۵۳ خط پنجم سراسری', 'EPC',
        '2024-03-01', '2026-12-20', '2027-03-15',
        68, 63,
        88, 82,
        72, 64,
        48, 37,
        15, 35, 50
    );

    -- 3. project_lifecycle_phases — weights (hybrid: PMO-set for Basic
    -- Design/EPC, schedule/step-based split for the rest, summing to 100)
    insert into project_lifecycle_phases (project_name, phase_code, weight_pct, planned_start, planned_finish, actual_start, actual_finish, gate_status, gate_requested_by, gate_requested_at) values
    (v_project, 'G1', 5,  '2024-03-01', '2024-04-15', '2024-03-01', '2024-04-10', 'passed', v_email, '2024-04-10'),
    (v_project, 'G2', 6,  '2024-04-16', '2024-06-30', '2024-04-16', '2024-06-25', 'passed', v_email, '2024-06-25'),
    (v_project, 'G3', 6,  '2024-07-01', '2024-09-15', '2024-07-01', '2024-09-10', 'passed', v_email, '2024-09-10'),
    (v_project, 'G5', 5,  '2025-05-01', '2025-07-31', '2025-05-01', '2025-07-28', 'passed', v_email, '2025-07-28'),
    (v_project, 'G7', 4,  '2026-11-01', '2027-01-31', null, null, 'not_ready', null, null),
    (v_project, 'G8', 4,  '2027-02-01', '2027-05-31', null, null, 'not_ready', null, null),
    (v_project, 'G9', 3,  '2027-06-01', '2027-08-15', null, null, 'not_ready', null, null);

    insert into project_lifecycle_phases (project_name, phase_code, weight_pct, planned_start, planned_finish, actual_start, contract_value, manual_actual_pct, gate_status, gate_requested_by, gate_requested_at) values
    (v_project, 'G4', 12, '2024-09-16', '2025-04-30', '2024-09-16', 480000000000, 95, 'passed', v_email, '2025-04-25');

    insert into project_lifecycle_phases (project_name, phase_code, weight_pct, planned_start, planned_finish, actual_start, gate_status) values
    (v_project, 'G6', 55, '2025-08-01', '2026-12-20', '2025-08-01', 'not_ready');

    -- 4. Gate decisions for the 5 already-passed gates
    insert into lifecycle_gate_decisions (project_name, phase_code, decision, decided_by, decided_at) values
    (v_project, 'G1', 'pass', v_email, '2024-04-10 10:00:00+00'),
    (v_project, 'G2', 'pass', v_email, '2024-06-25 10:00:00+00'),
    (v_project, 'G3', 'pass', v_email, '2024-09-10 10:00:00+00'),
    (v_project, 'G4', 'pass', v_email, '2025-04-25 10:00:00+00'),
    (v_project, 'G5', 'pass', v_email, '2025-07-28 10:00:00+00');

    -- 5. Basic Design (G4) periodic progress history
    insert into lifecycle_progress_history (project_name, phase_code, period_label, previous_pct, new_pct, recorded_by, recorded_at) values
    (v_project, 'G4', '1403 آبان - هفته ۲', null, 55, v_email, '2024-11-10 08:00:00+00'),
    (v_project, 'G4', '1403 دی - هفته ۲',   55,   74, v_email, '2025-01-05 08:00:00+00'),
    (v_project, 'G4', '1403 اسفند - هفته ۴', 74,  88, v_email, '2025-03-18 08:00:00+00'),
    (v_project, 'G4', '1404 فروردین - هفته ۴', 88, 95, v_email, '2025-04-20 08:00:00+00');

    -- 6. Item-level completion — G1..G3, G5: everything done (gates passed)
    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date)
    select v_project, phase_code, 'objective', id, 'completed', '2024-04-05', v_email, '2024-04-08' from lifecycle_objectives where phase_code = 'G1'
    union all
    select v_project, phase_code, 'output', id, 'verified', '2024-04-05', v_email, '2024-04-08' from lifecycle_outputs where phase_code = 'G1'
    union all
    select v_project, phase_code, 'criterion', id, 'verified', '2024-04-08', v_email, '2024-04-09' from lifecycle_criteria where phase_code = 'G1';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date)
    select v_project, phase_code, 'objective', id, 'completed', '2024-06-15', v_email, '2024-06-20' from lifecycle_objectives where phase_code = 'G2'
    union all
    select v_project, phase_code, 'output', id, 'verified', '2024-06-15', v_email, '2024-06-20' from lifecycle_outputs where phase_code = 'G2'
    union all
    select v_project, phase_code, 'criterion', id, 'verified', '2024-06-22', v_email, '2024-06-24' from lifecycle_criteria where phase_code = 'G2';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date)
    select v_project, phase_code, 'objective', id, 'completed', '2024-09-01', v_email, '2024-09-05' from lifecycle_objectives where phase_code = 'G3'
    union all
    select v_project, phase_code, 'output', id, 'verified', '2024-09-01', v_email, '2024-09-05' from lifecycle_outputs where phase_code = 'G3'
    union all
    select v_project, phase_code, 'criterion', id, 'verified', '2024-09-08', v_email, '2024-09-09' from lifecycle_criteria where phase_code = 'G3';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date)
    select v_project, phase_code, 'objective', id, 'completed', '2025-04-15', v_email, '2025-04-20' from lifecycle_objectives where phase_code = 'G4'
    union all
    select v_project, phase_code, 'output', id, 'verified', '2025-04-15', v_email, '2025-04-20' from lifecycle_outputs where phase_code = 'G4'
    union all
    select v_project, phase_code, 'criterion', id, 'verified', '2025-04-22', v_email, '2025-04-24' from lifecycle_criteria where phase_code = 'G4';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date)
    select v_project, phase_code, 'objective', id, 'completed', '2025-07-20', v_email, '2025-07-25' from lifecycle_objectives where phase_code = 'G5'
    union all
    select v_project, phase_code, 'output', id, 'verified', '2025-07-20', v_email, '2025-07-25' from lifecycle_outputs where phase_code = 'G5'
    union all
    select v_project, phase_code, 'criterion', id, 'verified', '2025-07-27', v_email, '2025-07-28' from lifecycle_criteria where phase_code = 'G5';

    -- 7. G6 (اجرای پروژه / EPC) — deliberately partial: high activity,
    -- gate NOT ready (both mandatory criteria still pending).
    insert into project_phase_items (project_name, phase_code, kind, item_id, status, completion_date, verified_by, verification_date, owner)
    select v_project, 'G6', 'objective', id,
        case seq when 1 then 'completed' when 2 then 'completed' when 3 then 'in_progress' else 'not_started' end,
        case seq when 1 then '2025-08-20'::date when 2 then '2025-09-10'::date else null end,
        case seq when 1 then v_email when 2 then v_email else null end,
        case seq when 1 then '2025-08-25'::date when 2 then '2025-09-12'::date else null end,
        'مجری طرح'
    from lifecycle_objectives where phase_code = 'G6';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, submitted_by, verified_by, verification_date)
    select v_project, 'G6', 'output', id,
        case seq when 1 then 'verified' when 2 then 'submitted' else 'pending' end,
        case seq when 1 then v_email when 2 then v_email else null end,
        case seq when 1 then v_email else null end,
        case seq when 1 then '2026-08-01'::date else null end
    from lifecycle_outputs where phase_code = 'G6';

    insert into project_phase_items (project_name, phase_code, kind, item_id, status, comment)
    select v_project, 'G6', 'criterion', id, 'pending',
        'در انتظار تکمیل فیزیکی اجرا و تایید ناظر — هنوز محقق نشده است.'
    from lifecycle_criteria where phase_code = 'G6';

    -- 8. G7..G9 — nothing started yet
    insert into project_phase_items (project_name, phase_code, kind, item_id, status)
    select v_project, phase_code, 'objective', id, 'not_started' from lifecycle_objectives where phase_code in ('G7', 'G8', 'G9')
    union all
    select v_project, phase_code, 'output', id, 'pending' from lifecycle_outputs where phase_code in ('G7', 'G8', 'G9')
    union all
    select v_project, phase_code, 'criterion', id, 'pending' from lifecycle_criteria where phase_code in ('G7', 'G8', 'G9');

    raise notice 'Lifecycle demo data seeded for project: %', v_project;
end $$;
