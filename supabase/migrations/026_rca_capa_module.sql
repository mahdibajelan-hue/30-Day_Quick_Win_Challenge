-- «تحلیل و آنالیز مشکلات پروژه» — redesign of the check-in form's old
-- "سؤالات کلیدی مدیریت" bottleneck fields into a full Problem -> Root Cause
-- -> CAPA -> Result -> Effectiveness cycle. Everything here is scoped to the
-- SAME period's bottleneck as the existing main_bottleneck/bottleneck_root_cause/
-- bottleneck_unlock_action columns (one row per check-in, same as those),
-- so no new table is needed — just structured jsonb alongside them.
--
-- bottleneck_root_cause and bottleneck_unlock_action are kept and still
-- written (a plain-text summary of rca_confirmed_causes / capa_corrective
-- respectively) purely so the existing exec-report row that already reads
-- them keeps working — the rich structured data below is what the new
-- module itself reads and writes.

alter table check_ins
    add column if not exists bottleneck_impact text,
    add column if not exists bottleneck_status text,
    add column if not exists bottleneck_criticality text,
    add column if not exists rca_method text,
    add column if not exists rca_ai_candidates jsonb,
    add column if not exists rca_five_why_steps jsonb,
    add column if not exists rca_fishbone jsonb,
    add column if not exists rca_confirmed_causes jsonb,
    add column if not exists capa_corrective jsonb,
    add column if not exists capa_preventive jsonb,
    add column if not exists capa_effectiveness text,
    add column if not exists capa_recurrence_reduced boolean,
    add column if not exists capa_value jsonb;

comment on column check_ins.bottleneck_impact is 'Short impact description of main_bottleneck, shown on the RCA module''s Problem card.';
comment on column check_ins.bottleneck_status is 'Current status of main_bottleneck (e.g. باز/در حال بررسی/حل‌شده), shown on the Problem card.';
comment on column check_ins.bottleneck_criticality is 'Criticality of main_bottleneck (کم/متوسط/زیاد/بحرانی), shown on the Problem card.';
comment on column check_ins.rca_method is 'Which root-cause method the respondent used: ai | five_why | fishbone.';
comment on column check_ins.rca_ai_candidates is 'jsonb array of AI-suggested root-cause candidates: [{cause, explanation, evidence, probability, impact, confidence, suggested_action, status: pending|confirmed|edited}].';
comment on column check_ins.rca_five_why_steps is 'jsonb array of {n, question, answer} for the 5-Why investigation path.';
comment on column check_ins.rca_fishbone is 'jsonb: {activeCategories: [...], causes: {categoryKey: [{id, text, whys: [{q,a}], confirmed}]}}.';
comment on column check_ins.rca_confirmed_causes is 'jsonb array of {text, evidence, source} — the unified root-cause outcome regardless of which method (ai/five_why/fishbone) produced it.';
comment on column check_ins.capa_corrective is 'jsonb: {action, owner, due_date, priority, status, evidence, completion_date} — Corrective Action tied to rca_confirmed_causes.';
comment on column check_ins.capa_preventive is 'jsonb: {action, owner, due_date, priority, status, evidence, completion_date} — Preventive Action tied to rca_confirmed_causes.';
comment on column check_ins.capa_effectiveness is 'مؤثر | تا حدی مؤثر | غیرمؤثر — effectiveness check after CAPA completion.';
comment on column check_ins.capa_recurrence_reduced is 'Whether the respondent judged recurrence risk reduced after CAPA; false/null prompts a return to root-cause analysis in the UI.';
comment on column check_ins.capa_value is 'jsonb: {problem_solved, time_saved_days, cost_avoided_rial, risk_reduced, rework_reduced, productivity_increased} — lean, measurable value/impact of the resolved problem.';
