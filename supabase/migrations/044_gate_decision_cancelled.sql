-- ============================================================
-- «اگر گیتی به اشتباه تایید نهایی شده بود ادمین قابلیت کنسل کردن آن را
-- داشته باشد» — the app's cancel-gate-pass action records a 'cancelled'
-- lifecycle_gate_decisions row, but migration 033 only allowed
-- ('pass', 'conditional', 'return') in that column's check constraint,
-- so every cancel attempt failed with a check-constraint violation.
-- ============================================================

alter table lifecycle_gate_decisions
    drop constraint lifecycle_gate_decisions_decision_check;

alter table lifecycle_gate_decisions
    add constraint lifecycle_gate_decisions_decision_check
    check (decision in ('pass', 'conditional', 'return', 'cancelled'));
