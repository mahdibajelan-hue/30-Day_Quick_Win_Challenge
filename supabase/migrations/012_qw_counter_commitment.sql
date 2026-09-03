-- ============================================================
-- Migration: پیشنهاد Quick Win asks the مجری طرح for support, but until
-- now that ask was one-sided — nothing captured what the requesting
-- organization itself commits to in return. Adds a matching
-- counter-commitment column next to the existing support_needed one,
-- on both check_ins (the live proposal) and quick_win_decisions (the
-- snapshot taken when a proposal is picked as the winner).
-- ============================================================

alter table check_ins
    add column if not exists counter_commitment text;

alter table quick_win_decisions
    add column if not exists selected_counter_commitment text;
