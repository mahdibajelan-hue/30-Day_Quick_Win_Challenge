// Supabase Edge Function: notify-overdue-tasks
//
// Not called from the app itself — this is a system job meant to be
// triggered once a day by a Supabase Cron schedule (pg_cron + pg_net,
// see supabase/setup_overdue_task_cron.sql). It finds every
// quick_win_tasks row that's still open past its due_date and hasn't
// been notified about yet, and emails via Resend whoever still owes an
// action: the responsible person (cc admins) while the task hasn't been
// submitted yet, or admins directly once it's «در انتظار تایید» — their
// final approval is the only thing left — then stamps overdue_notified_at
// so the same task is only ever emailed about once.
//
// There is no logged-in caller here (it's a scheduled job, not a user
// action), so — unlike analyze-project — using the service-role key is
// the correct choice: it needs to read across every project's tasks and
// every admin's email regardless of who (if anyone) is logged in.
//
// Deploy: `supabase functions deploy notify-overdue-tasks` (or paste into
// the Supabase dashboard). Required secrets:
//   - RESEND_API_KEY: API key from resend.com (used to actually send mail)
//   - RESEND_FROM: the "from" address, e.g. "پیگیری Quick Win <alerts@yourdomain.com>"
//     (must be on a domain verified in Resend)
//   - CRON_SECRET: any random string you choose — the cron job must send
//     it back in the x-cron-secret header, so this endpoint can't be
//     triggered (and made to send mail) by anyone who finds its URL.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM = Deno.env.get("RESEND_FROM") ?? "پیگیری Quick Win <onboarding@resend.dev>";
const CRON_SECRET = Deno.env.get("CRON_SECRET");

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
function buildEmail(task: any): { subject: string; html: string } {
  const daysOverdue = Math.max(
    0,
    Math.floor((Date.now() - new Date(task.due_date).getTime()) / 86400000),
  );
  const pendingApproval = task.status === "در انتظار تایید";
  const subject = pendingApproval
    ? `⚠️ در انتظار تایید نهایی (معوق): ${task.title} — پروژه ${task.project_name}`
    : `⚠️ اقدام معوق: ${task.title} — پروژه ${task.project_name}`;
  const closingLine = pendingApproval
    ? "<p>این اقدام قبلاً توسط مسئول ثبت شده و صرفاً منتظر تایید نهایی ادمین است.</p>"
    : "<p>لطفاً وضعیت این اقدام را در سامانه بروزرسانی کنید.</p>";
  const html = `
    <div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;font-size:14px;line-height:1.8;color:#1e293b">
      <p>یک اقدام از تایم‌لاین پیگیری اجرای Quick Win هنوز تا موعد مقررش به تایید نهایی نرسیده است:</p>
      <ul>
        <li><b>پروژه:</b> ${task.project_name}</li>
        <li><b>عنوان اقدام:</b> ${task.title}</li>
        <li><b>مسئول:</b> ${task.responsible_name}</li>
        <li><b>موعد انجام:</b> ${task.due_date}</li>
        <li><b>مدت تأخیر:</b> ${daysOverdue} روز</li>
      </ul>
      ${closingLine}
    </div>`;
  return { subject, html };
}

Deno.serve(async (req) => {
  try {
    if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    if (!RESEND_API_KEY) {
      return jsonResponse({ error: "کلید RESEND_API_KEY هنوز در تنظیمات Supabase (Secrets) ثبت نشده است." }, 500);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: overdueTasks, error: tasksErr } = await supabase
      .from("quick_win_tasks")
      .select("id, project_name, title, responsible_name, responsible_email, due_date, status")
      .lt("due_date", new Date().toISOString().slice(0, 10))
      .neq("status", "انجام‌شده")
      .is("overdue_notified_at", null);

    if (tasksErr) return jsonResponse({ error: tasksErr.message }, 500);
    if (!overdueTasks || overdueTasks.length === 0) {
      return jsonResponse({ notified: 0 });
    }

    const { data: admins } = await supabase.from("app_users").select("email").eq("role", "admin");
    // deno-lint-ignore no-explicit-any
    const adminEmails = (admins || []).map((a: any) => a.email).filter(Boolean);

    let notified = 0;
    const errors: string[] = [];

    for (const task of overdueTasks) {
      const { subject, html } = buildEmail(task);
      // Once the responsible person has already submitted the task for
      // approval, the ball is in the admin's court — address the reminder
      // to admins instead of nagging someone who already did their part.
      const pendingApproval = task.status === "در انتظار تایید";
      const toEmails = pendingApproval ? adminEmails : [task.responsible_email];
      const ccEmails = pendingApproval ? [] : adminEmails;
      if (toEmails.length === 0) continue;

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          Authorization: `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify({
          from: RESEND_FROM,
          to: toEmails,
          cc: ccEmails,
          subject,
          html,
        }),
      });

      if (!res.ok) {
        errors.push(`task ${task.id}: ${await res.text()}`);
        continue;
      }

      await supabase
        .from("quick_win_tasks")
        .update({ overdue_notified_at: new Date().toISOString() })
        .eq("id", task.id);
      notified++;
    }

    return jsonResponse({ notified, total_overdue: overdueTasks.length, errors });
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
