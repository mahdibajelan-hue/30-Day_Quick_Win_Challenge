-- ============================================================
-- Migration: check_ins.financial_progress is now calculated from
-- spend-to-date rather than typed directly. Adds the two raw spend
-- columns (billion Rial / million Euro) the app now collects instead
-- of a raw percentage; financial_progress itself is unchanged (still
-- numeric 0-100), just computed client-side from these against the
-- project's current contract amount (client_reports) before insert.
-- ============================================================

alter table check_ins
    add column if not exists financial_spent_rial numeric,
    add column if not exists financial_spent_eur numeric;

comment on column check_ins.financial_spent_rial is 'billion Rial spent to date';
comment on column check_ins.financial_spent_eur is 'million Euro spent to date';
