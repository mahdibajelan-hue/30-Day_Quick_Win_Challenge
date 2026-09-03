-- ============================================================
-- Migration: flags a single project as the built-in «پروژه راهنما»
-- (guide/demo project) — a fully-filled-out example meant to teach new
-- managers how to complete every form. It should be visible like any
-- other project everywhere in the app, except نمای کلی (Overview),
-- whose whole point is an honest aggregate of real project data —
-- see getGuideProjectNames() / loadOverview() / loadTrackingData() in
-- index.html.
-- ============================================================

alter table projects
    add column if not exists is_guide boolean not null default false;
