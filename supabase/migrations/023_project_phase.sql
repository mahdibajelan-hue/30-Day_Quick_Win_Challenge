-- Redesign backlog (P1): "شرطی‌سازی ۱۰ جبهه کاری بر اساس فاز پروژه" — the
-- periodic check-in form always shows all 10 «جبهه کاری» (work-front) rows
-- even for a project still in engineering/procurement, where they're not
-- yet meaningful. Conditioning that block needs the project's current
-- phase to condition on.
--
-- Default/backfill is 'اجرا' (execution) rather than an earlier phase: this
-- column doesn't exist yet, so every *existing* project must land somewhere,
-- and defaulting to the phase that currently shows the fronts block keeps
-- today's behavior for every project already in flight. An admin then
-- narrows a specific project to an earlier phase explicitly, from the
-- project card in مدیریت کاربران, only if that project is actually not
-- there yet — nothing is hidden by surprise.
alter table projects
    add column if not exists current_phase text not null default 'اجرا'
    check (current_phase in ('مهندسی', 'تأمین', 'اجرا', 'تکمیل‌شده'));
