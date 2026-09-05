-- ============================================================
-- ONE-TIME MANUAL SETUP — do not run this as-is, it will fail.
-- This is not part of the automatic migration sequence (016 only
-- enables the pg_cron/pg_net extensions) because it needs three values
-- that are specific to YOUR Supabase project and must never be
-- committed to git as real secrets:
--
--   1. <YOUR-PROJECT-REF>  — from your Supabase project's API URL,
--      https://<YOUR-PROJECT-REF>.supabase.co
--   2. <YOUR-CRON-SECRET>  — any random string you choose yourself
--      (e.g. generate one with `openssl rand -hex 32`). Set the exact
--      same value as the CRON_SECRET secret on the notify-overdue-tasks
--      Edge Function (Project Settings → Edge Functions → Secrets),
--      so the function can tell this scheduled call apart from a
--      random person hitting its URL directly.
--   3. <YOUR-ANON-KEY>  — the project's public "anon" key, from
--      Project Settings → API → Project API keys. This is NOT a
--      secret (it's the same key the frontend already ships to every
--      browser) — it's required only because every Edge Function sits
--      behind Supabase's own gateway, which rejects any request with
--      no Authorization header at all before it ever reaches your
--      function's code. The x-cron-secret header above is still what
--      actually authorizes this call inside the function itself.
--
-- Steps:
--   1. Deploy the notify-overdue-tasks Edge Function and set its
--      GMAIL_USER, GMAIL_APP_PASSWORD, and CRON_SECRET secrets.
--   2. Replace all three placeholders below with your real values.
--   3. Run the resulting SQL once in the Supabase SQL Editor.
--
-- This schedules the function to run every day at 06:00 UTC; adjust
-- the cron expression if you want a different time.
-- ============================================================

select cron.schedule(
    'notify-overdue-quick-win-tasks',
    '0 6 * * *',
    $$
    select net.http_post(
        url := 'https://<YOUR-PROJECT-REF>.supabase.co/functions/v1/notify-overdue-tasks',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer <YOUR-ANON-KEY>',
            'x-cron-secret', '<YOUR-CRON-SECRET>'
        ),
        body := '{}'::jsonb
    );
    $$
);

-- To check it's registered:
--   select * from cron.job where jobname = 'notify-overdue-quick-win-tasks';
-- To remove it later:
--   select cron.unschedule('notify-overdue-quick-win-tasks');
