-- ============================================================
-- Demo data for the Lifecycle Master Plan (Gantt) — NOT a migration;
-- run manually in the Supabase SQL Editor AFTER 038_lifecycle_schedule.sql
-- and seed_lifecycle_demo_project.sql have both been applied.
--
-- Builds a small but realistic 3-level schedule tree under G6 (اجرای
-- پروژه / EPC) of the demo project — three overlapping sub-phases
-- (Engineering / Procurement / Construction, exactly the "phases don't
-- have to be sequential" case the Master Plan spec calls out), with
-- Procurement drilled down one further level into real activities, plus
-- one FS dependency with a Lead (a 5-day overlap) and one SS dependency
-- with a 22-day Lag — so opening the Gantt tab immediately shows both
-- overlap and both a Lag and a Lead in action, not just a placeholder.
--
-- Safe to re-run: clears any previous schedule rows for this project
-- before reinserting (dependencies first, since they reference items).
-- ============================================================

do $$
declare
    v_project text := 'پروژه احداث ایستگاه رسیور گاز کیلومتر ۵۳ خط پنجم سراسری (نمونه آزمایشی)';
    v_eng_id bigint;
    v_proc_id bigint;
    v_constr_id bigint;
    v_proc_tender_id bigint;
    v_proc_rotating_id bigint;
    v_proc_instrument_id bigint;
begin
    delete from lifecycle_schedule_dependencies where project_name = v_project;
    delete from lifecycle_schedule_items where project_name = v_project;

    -- Top-level sub-phases under G6 — note Procurement starts well before
    -- Engineering finishes, and Construction starts before Procurement
    -- finishes: this is the "non-sequential / overlap-capable" case.
    insert into lifecycle_schedule_items (project_name, phase_code, title, planned_start, planned_finish, weight_pct)
        values (v_project, 'G6', 'مهندسی تفصیلی (Detailed Engineering)', '2025-08-01', '2026-02-15', 15)
        returning id into v_eng_id;
    insert into lifecycle_schedule_items (project_name, phase_code, title, planned_start, planned_finish, weight_pct)
        values (v_project, 'G6', 'تدارکات (Procurement)', '2025-11-01', '2026-08-01', 35)
        returning id into v_proc_id;
    insert into lifecycle_schedule_items (project_name, phase_code, title, planned_start, planned_finish, weight_pct)
        values (v_project, 'G6', 'ساخت و نصب (Construction)', '2026-02-01', '2026-12-20', 50)
        returning id into v_constr_id;

    -- Activities under Engineering
    insert into lifecycle_schedule_items (project_name, phase_code, parent_id, title, planned_start, planned_finish, weight_pct, manual_actual_pct) values
        (v_project, 'G6', v_eng_id, 'طراحی پایه تفصیلی خطوط لوله', '2025-08-01', '2025-11-01', 60, 100),
        (v_project, 'G6', v_eng_id, 'طراحی تفصیلی ابزار دقیق و برق', '2025-09-15', '2026-02-15', 40, 70);

    -- Activities under Procurement (the drill-down example)
    insert into lifecycle_schedule_items (project_name, phase_code, parent_id, title, planned_start, planned_finish, weight_pct, manual_actual_pct)
        values (v_project, 'G6', v_proc_id, 'تهیه اسناد مناقصه تجهیزات', '2025-11-01', '2025-12-15', 20, 100)
        returning id into v_proc_tender_id;
    insert into lifecycle_schedule_items (project_name, phase_code, parent_id, title, planned_start, planned_finish, weight_pct, manual_actual_pct)
        values (v_project, 'G6', v_proc_id, 'خرید تجهیزات دوار', '2025-12-10', '2026-04-01', 45, 60)
        returning id into v_proc_rotating_id;
    insert into lifecycle_schedule_items (project_name, phase_code, parent_id, title, planned_start, planned_finish, weight_pct, manual_actual_pct)
        values (v_project, 'G6', v_proc_id, 'خرید تجهیزات ابزار دقیق', '2026-01-01', '2026-06-01', 35, 30)
        returning id into v_proc_instrument_id;

    -- One FS dependency with a 5-day Lead (successor starts 5 days
    -- before the predecessor's finish, matching the dates above), and
    -- one SS dependency with a 22-day Lag between the two purchases.
    insert into lifecycle_schedule_dependencies (project_name, predecessor_id, successor_id, dep_type, lag_days) values
        (v_project, v_proc_tender_id, v_proc_rotating_id, 'FS', -5),
        (v_project, v_proc_rotating_id, v_proc_instrument_id, 'SS', 22);
end $$;
