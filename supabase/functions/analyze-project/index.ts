// Supabase Edge Function: analyze-project
//
// Called from the app's admin-only "🤖 تحلیل هوشمند" button. Fetches every
// organization's latest check-in for a project and asks either Gemini or
// ChatGPT (caller's choice) for a short analytical report. Whichever
// provider's API key stays server-side (in this function's secrets) and is
// never exposed to the browser.
//
// Deploy: paste this file's content into a new Edge Function named
// "analyze-project" in the Supabase dashboard (or `supabase functions deploy
// analyze-project` if using the CLI), then set at least one of the secrets
// GEMINI_API_KEY / OPENAI_API_KEY (only the one(s) you actually plan to use).
// Note: Gemini's API has an ongoing free tier (rate-limited); OpenAI's API
// generally requires a billed account, so "ChatGPT" here is only free if
// your OpenAI account happens to have free credit.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

// Both Gemini and OpenAI occasionally answer a request with 503 ("model
// overloaded" / "try again later") purely due to transient load on their
// end — the request itself was never even processed, so retrying costs
// almost nothing. Only 503 is retried; any other status (auth, quota,
// bad request, ...) is a real error retrying won't fix.
async function fetchWithRetry(url: string, options: RequestInit, maxRetries = 2): Promise<Response> {
  let res: Response;
  for (let attempt = 0; ; attempt++) {
    res = await fetch(url, options);
    if (res.ok || res.status !== 503 || attempt >= maxRetries) return res;
    await new Promise((r) => setTimeout(r, 800 * 2 ** attempt));
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Unauthorized" }, 401);

    // Client scoped to the caller's own JWT: identifies who is asking and
    // lets Postgres RLS decide what they're allowed to read.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return jsonResponse({ error: "Unauthorized" }, 401);

    const { data: profile } = await supabase
      .from("app_users")
      .select("role")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!profile || profile.role !== "admin") {
      return jsonResponse({ error: "این تحلیل فقط برای ادمین سامانه در دسترس است." }, 403);
    }

    const { project_name, provider } = await req.json();
    if (!project_name) return jsonResponse({ error: "project_name الزامی است." }, 400);
    const chosenProvider = provider === "openai" ? "openai" : "gemini";

    const { data: checkins } = await supabase
      .from("check_ins")
      .select("*")
      .eq("project_name", project_name)
      .order("created_at", { ascending: true });

    if (!checkins || checkins.length === 0) {
      return jsonResponse({ error: "برای این پروژه هنوز گزارشی ثبت نشده است." }, 404);
    }

    const { data: decision } = await supabase
      .from("quick_win_decisions")
      .select("*")
      .eq("project_name", project_name)
      .maybeSingle();

    const { data: progress } = await supabase
      .from("quick_win_progress")
      .select("*")
      .eq("project_name", project_name)
      .order("created_at", { ascending: true });

    const { data: clientReport } = await supabase
      .from("client_reports")
      .select("*")
      .eq("project_name", project_name)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    // The app's check-in form was split into two independent forms (a
    // periodic status report and a Quick Win proposal), so a given
    // organization's "current perspective" is now spread across two rows
    // instead of one. Fold the latest row of each kind back into a single
    // composite record per org — the two forms write disjoint columns, so
    // overlaying the Quick Win row's non-null fields onto the periodic
    // row's is a safe, order-independent merge.
    // deno-lint-ignore no-explicit-any
    const latestByOrg: Record<string, any> = {};
    // deno-lint-ignore no-explicit-any
    const rowsByOrg: Record<string, any[]> = {};
    for (const c of checkins) (rowsByOrg[c.organization] ??= []).push(c);
    for (const [org, rows] of Object.entries(rowsByOrg)) {
      const periodic = [...rows].reverse().find((r) => r.main_bottleneck != null);
      const qw = [...rows].reverse().find((r) => r.quick_win_title != null);
      if (!periodic) { latestByOrg[org] = qw; continue; }
      if (!qw) { latestByOrg[org] = periodic; continue; }
      const merged = { ...periodic };
      for (const [k, v] of Object.entries(qw)) if (v !== null && v !== undefined) merged[k] = v;
      latestByOrg[org] = merged;
    }

    // deno-lint-ignore no-explicit-any
    function summarizeStatusGroup(group: any): string {
      if (!group) return "-";
      return Object.entries(group)
        // deno-lint-ignore no-explicit-any
        .map(([k, v]: [string, any]) => `${k}=${v?.status ?? "-"}${v?.issue ? `(${v.issue})` : ""}`)
        .join(", ");
    }
    // deno-lint-ignore no-explicit-any
    function summarizeIssues(issues: any): string {
      if (!issues || !issues.length) return "-";
      // deno-lint-ignore no-explicit-any
      return issues.map((i: any, idx: number) => `  ${idx + 1}) ${i.description} [اثر: ${(i.impact || []).join(",")}] شدت:${i.severity}`).join("\n");
    }
    // deno-lint-ignore no-explicit-any
    function summarizeRisks(risks: any): string {
      if (!risks || !risks.length) return "-";
      // deno-lint-ignore no-explicit-any
      return risks.map((r: any, idx: number) => `  ${idx + 1}) ${r.risk} (احتمال:${r.probability}, اثر:${r.impact}, سطح:${r.level}) اقدام فعلی:${r.current_action || "-"}`).join("\n");
    }

    const perspectiveText = Object.entries(latestByOrg)
      .map(([org, c]: [string, any]) => `
### دیدگاه ${org}
- پاسخ‌دهنده: ${c.respondent || "-"} (${c.respondent_position || "-"})
- وضعیت حوزه‌ها (X-Ray): ${summarizeStatusGroup(c.area_status)}
- وضعیت جبهه‌های کاری: ${summarizeStatusGroup(c.work_fronts)}
- پیشرفت برنامه‌ای: ${c.planned_progress ?? "-"}% | پیشرفت فیزیکی واقعی: ${c.physical_progress}%
- تاریخ پیش‌بینی فعلی تکمیل: ${c.forecast_completion_date}
- رویداد HSE: ${c.hse_incident ? "بله - " + c.hse_incident_note : "خیر"}
- سه مسئله اصلی:\n${summarizeIssues(c.issues)}
- سه ریسک اصلی:\n${summarizeRisks(c.risks)}
- اگر اقدامی نشود (افق سه‌ماهه): ${c.q_negative_event || "-"}
- گلوگاه فعلی: ${c.main_bottleneck} | علت ریشه‌ای: ${c.bottleneck_root_cause || "-"} | راه باز کردن: ${c.bottleneck_unlock_action || "-"}
- نیاز به تصمیم مدیریت ارشد (اولویت ${c.senior_decision_priority || "-"}): ${c.senior_decision_needed || "-"}
- ریسک پیش‌رو (شدت ${c.risk_severity ?? "-"}/۵): ${c.top_risk}
- پیشنهاد Quick Win: ${c.quick_win_title} — اقدام: ${c.action_details} — چرا: ${c.qw_rationale || "-"} — نتیجه ۳۰ روزه: ${c.tangible_result}
- برنامه تحقق: مسئول=${c.plan_responsible || "-"}, تاریخ هدف=${c.plan_target_date || "-"}, خروجی=${c.plan_deliverable || "-"}
- اثر برآوردی: تأخیر=${c.impact_delay_days ?? "-"} روز, پیشرفت=${c.impact_progress_increase ?? "-"}%, هزینه=${c.impact_cost_avoided ?? "-"} ریال
- حمایت لازم: ${c.support_needed} | برآورد زمان تحقق: ${c.time_estimate || "-"}`)
      .join("\n");

    const decisionText = decision
      ? `\nQuick Win برگزیده فعلی: ${decision.selected_title} (${decision.selected_organization}) — دلیل: ${decision.rationale || "-"} — مهلت: ${decision.target_date}`
      : "\nهنوز Quick Win‌ی برای این پروژه انتخاب نشده است.";

    const progressText = progress && progress.length > 0
      // deno-lint-ignore no-explicit-any
      ? "\nتاریخچه پایش:\n" + progress.map((p: any) => `- ${String(p.created_at).slice(0, 10)}: ${p.status}, ${p.progress_percent}% — ${p.note || ""}`).join("\n")
      : "";

    // deno-lint-ignore no-explicit-any
    function buildClientReportText(cr: any): string {
      if (!cr) return "\nفرم اول (اطلاعات پایه پروژه) هنوز توسط کارفرما ثبت نشده است.";
      const variance = (typeof cr.progress_physical === "number" && typeof cr.progress_planned === "number")
        ? cr.progress_physical - cr.progress_planned
        : null;
      const elapsedPercent = (cr.contract_duration_months && cr.elapsed_months != null)
        ? Math.round((cr.elapsed_months / cr.contract_duration_months) * 100)
        : null;
      return `
### اطلاعات پایه و پیشرفت رسمی پروژه (فرم اول کارفرما)
- نام طرح: ${cr.plan_name || "-"} | شماره قرارداد: ${cr.contract_number || "-"} | نوع قرارداد: ${cr.contract_type === "سایر" ? cr.contract_type_other : cr.contract_type || "-"}
- پیمانکار: ${cr.contractor_name || "-"} | مشاور: ${cr.consultant_name || "-"} | مدیر پروژه کارفرما: ${cr.client_pm_name || "-"}
- مبلغ اولیه/فعلی قرارداد — ریالی (میلیارد ریال): ${cr.contract_initial_amount_rial ?? "-"} / ${cr.contract_current_amount_rial ?? "-"}
- مبلغ اولیه/فعلی قرارداد — ارزی (میلیون یورو): ${cr.contract_initial_amount_eur ?? "-"} / ${cr.contract_current_amount_eur ?? "-"}
- تاریخ شروع/پایان قراردادی: ${cr.contract_start_date || "-"} تا ${cr.contract_end_date || "-"}
- مدت قرارداد: ${cr.contract_duration_months ?? "-"} ماه | مدت سپری‌شده: ${cr.elapsed_months ?? "-"} ماه${elapsedPercent !== null ? ` (${elapsedPercent}% از مدت قرارداد)` : ""}
- پیشرفت برنامه‌ای رسمی: ${cr.progress_planned ?? "-"}% | پیشرفت واقعی رسمی: ${cr.progress_physical ?? "-"}%${variance !== null ? ` (انحراف ${variance > 0 ? "+" : ""}${variance}%)` : ""}
- پیشرفت مهندسی: ${cr.progress_engineering ?? "-"}% | پیشرفت تأمین: ${cr.progress_procurement ?? "-"}% | پیشرفت اجرا: ${cr.progress_construction ?? "-"}%
- مهم‌ترین Milestone پیش‌رو: ${cr.milestone_name || "-"} — تاریخ برنامه‌ای ${cr.milestone_planned_date || "-"} — وضعیت: ${cr.milestone_status || "-"}${cr.milestone_delay_days ? ` (برآورد تأخیر ${cr.milestone_delay_days} روز)` : ""}`;
    }

    const clientReportText = buildClientReportText(clientReport);

    const prompt = `شما یک متخصص ارشد مدیریت پورتفولیوی پروژه‌های خط انتقال گاز هستید. اطلاعات زیر مربوط به پروژه «${project_name}» است: هم اطلاعات رسمی قرارداد و پیشرفت که توسط برنامه‌ریزی و کنترل پروژه کارفرما ثبت شده، و هم گزارش‌های دوره‌ای که کارفرما، مشاور و پیمانکار هرکدام به‌طور مستقل از دیدگاه خودشان ثبت کرده‌اند:
${clientReportText}
${perspectiveText}
${decisionText}
${progressText}

با استفاده از تمام اطلاعات بالا (اطلاعات قراردادی/رسمی + هر سه دیدگاه)، یک گزارش تحلیلی جامع و کامل به فارسی تولید کن، دقیقاً با این ساختار:

۱. **خلاصه مدیریتی** — وضعیت کلی پروژه در ۲ تا ۳ جمله (سبز/زرد/قرمز و چرا).
۲. **وضعیت قراردادی و زمان‌بندی** — مقایسه پیشرفت رسمی (فرم کارفرما) با پیشرفت گزارش‌شده توسط هر سه رکن، انحراف از برنامه، درصد مدت سپری‌شده نسبت به پیشرفت واقعی، و ریسک Milestone پیش‌رو.
۳. **تناقض‌های کلیدی بین دیدگاه‌ها** — هر عدد یا برداشتی که بین کارفرما، مشاور و پیمانکار (یا بین گزارش رسمی کارفرما و ادعای خودشان) مغایرت دارد را دقیقاً با اسم و عدد ذکر کن.
۴. **گلوگاه‌ها و جبهه‌های بحرانی** — بر اساس وضعیت حوزه‌ها (X-Ray) و جبهه‌های کاری هر سه رکن، کدام حوزه‌ها/جبهه‌ها در بیش از یک دیدگاه قرمز یا زرد گزارش شده‌اند.
۵. **مهم‌ترین ریسک‌ها و مسائل باز** — از میان ریسک‌ها و مسائل سه‌گانه‌ی هر رکن، مهم‌ترین‌ها را دسته‌بندی و اولویت‌بندی کن (تکراری‌ها را یکی کن).
۶. **ارزیابی مقایسه‌ای پیشنهادهای Quick Win** — سه پیشنهاد Quick Win را با هم مقایسه کن و مشخص کن کدام بیشترین اثر/کمترین زمان را دارد و چرا (مستقل از اینکه فعلاً کدام برگزیده شده).
۷. **پیشنهاد اقدام اولویت‌دار برای ۳۰ روز آینده** — مشخص، عملیاتی، و با ذکر مسئول پیشنهادی.
۸. **جمع‌بندی و توصیه به مدیریت ارشد** — چه تصمیمی از مدیریت ارشد لازم است و چرا فوریت دارد.

خروجی باید دقیق، مستند به اعداد واقعی داده‌شده، و قابل ارائه مستقیم به مدیر اجرایی طرح باشد — از تکرار کلی‌گویی بدون عدد یا مصداق پرهیز کن.`;

    let analysisText: string;

    if (chosenProvider === "openai") {
      const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
      if (!OPENAI_API_KEY) {
        return jsonResponse({ error: "کلید OpenAI هنوز در تنظیمات Supabase (Secrets) ثبت نشده است." }, 500);
      }

      const aiRes = await fetchWithRetry("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "Authorization": `Bearer ${OPENAI_API_KEY}`,
        },
        // gpt-4o-mini is a good low-cost default; change if your account uses a different model.
        body: JSON.stringify({
          model: "gpt-4o-mini",
          max_tokens: 2000,
          messages: [{ role: "user", content: prompt }],
        }),
      });

      if (!aiRes.ok) {
        if (aiRes.status === 503) {
          return jsonResponse({ error: "سرویس ChatGPT در حال حاضر با ترافیک بالا مواجه است. این وضعیت موقتی است و از سمت OpenAI رخ می‌دهد، نه سامانه ما — لطفاً چند لحظه دیگر دوباره تلاش کنید." }, 503);
        }
        const errText = await aiRes.text();
        return jsonResponse({ error: "خطا در فراخوانی ChatGPT: " + errText }, 502);
      }

      const aiData = await aiRes.json();
      analysisText = aiData.choices?.[0]?.message?.content || "پاسخی دریافت نشد.";
    } else {
      const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
      if (!GEMINI_API_KEY) {
        return jsonResponse({ error: "کلید Gemini هنوز در تنظیمات Supabase (Secrets) ثبت نشده است." }, 500);
      }

      // Check ai.google.dev/models for the current recommended free-tier
      // model name if this one starts returning a "model not found" error
      // (Google periodically retires older model versions).
      const aiRes = await fetchWithRetry(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
          }),
        },
      );

      if (!aiRes.ok) {
        if (aiRes.status === 503) {
          return jsonResponse({ error: "سرویس Gemini در حال حاضر با ترافیک بالا مواجه است. این وضعیت موقتی است و از سمت Google رخ می‌دهد، نه سامانه ما — لطفاً چند لحظه دیگر دوباره تلاش کنید." }, 503);
        }
        const errText = await aiRes.text();
        return jsonResponse({ error: "خطا در فراخوانی Gemini: " + errText }, 502);
      }

      const aiData = await aiRes.json();
      analysisText = aiData.candidates?.[0]?.content?.parts?.[0]?.text || "پاسخی دریافت نشد.";
    }

    return jsonResponse({ analysis: analysisText, provider: chosenProvider });
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
