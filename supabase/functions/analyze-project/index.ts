// Supabase Edge Function: analyze-project
//
// Called from the app's admin-only "🤖 تحلیل هوشمند" button. Fetches every
// organization's latest check-in for a project (plus اطلاعات پایه/client_reports,
// the selected Quick Win decision, and its progress log) and asks either
// Gemini or ChatGPT (caller's choice) to synthesize a deep, structured
// analysis — not just a summary of each report on its own, but the kind of
// cross-perspective pattern a busy executive skimming three separate forms
// would likely miss. Whichever provider's API key stays server-side (in
// this function's secrets) and is never exposed to the browser.
//
// The result is cached in the ai_analyses table (see migration
// 015_ai_analyses.sql) keyed by project+provider, and only regenerated when
// the underlying data has changed since the cached run, or the caller
// explicitly asks for force_refresh — so the paid AI call only happens when
// there's actually something new to analyze.
//
// Deploy: paste this file's content into the "analyze-project" Edge
// Function in the Supabase dashboard (or `supabase functions deploy
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
    // lets Postgres RLS decide what they're allowed to read. Deliberately
    // never the service-role key — this function must stay exactly as
    // restricted as a logged-in admin using the app normally, since it
    // reads every organization's private data for a project at once.
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

    const { project_name, provider, force_refresh } = await req.json();
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

    // Newest timestamp across every source row this analysis depends on —
    // used below to tell a genuinely stale cache entry from a fresh one.
    const timestamps: string[] = [];
    // deno-lint-ignore no-explicit-any
    checkins.forEach((c: any) => c.created_at && timestamps.push(c.created_at));
    if (decision?.created_at) timestamps.push(decision.created_at);
    // deno-lint-ignore no-explicit-any
    (progress || []).forEach((p: any) => p.created_at && timestamps.push(p.created_at));
    if (clientReport?.created_at) timestamps.push(clientReport.created_at);
    const newestSourceAt = timestamps.length
      ? timestamps.reduce((a, b) => (a > b ? a : b))
      : new Date(0).toISOString();

    // ---- Cache check (skipped entirely on force_refresh) ----
    // Soft-fail on purpose: caching is an optimization, never a dependency
    // — if the ai_analyses table isn't there yet (migration not applied)
    // or the read errors for any other reason, just fall through to a
    // live call instead of breaking the whole feature.
    if (!force_refresh) {
      try {
        const { data: cached } = await supabase
          .from("ai_analyses")
          .select("analysis_json, source_data_at, created_at")
          .eq("project_name", project_name)
          .eq("provider", chosenProvider)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (cached && cached.source_data_at >= newestSourceAt) {
          // A previous, incompatible deployment of this function could have
          // stored analysis_json as a JSON *string* (double-encoded) instead
          // of an object — unwrap it so an old row still renders correctly.
          let cachedAnalysis = cached.analysis_json;
          if (typeof cachedAnalysis === "string") {
            try {
              cachedAnalysis = JSON.parse(cachedAnalysis);
            } catch (_e) {
              // leave as-is
            }
          }
          return jsonResponse({
            analysis: cachedAnalysis,
            provider: chosenProvider,
            source: "cache",
            cached_at: cached.created_at,
          });
        }
      } catch (_e) {
        // fall through to a live call
      }
    }

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

    const prompt = `شما یک متخصص ارشد مدیریت پورتفولیوی پروژه‌های خط انتقال گاز هستید. اطلاعات زیر مربوط به پروژه «${project_name}» است: هم اطلاعات رسمی قرارداد و پیشرفت که توسط برنامه‌ریزی و کنترل پروژه کارفرما ثبت شده (فرم اطلاعات پایه)، و هم گزارش‌های دوره‌ای که کارفرما، مشاور و پیمانکار هرکدام به‌طور مستقل از دیدگاه خودشان ثبت کرده‌اند (فرم اطلاعات تکمیلی و پیشنهاد Quick Win):
${clientReportText}
${perspectiveText}
${decisionText}
${progressText}

با استفاده از تمام اطلاعات بالا، یک تحلیل عمیق و کاملاً مستند تهیه کن. هدف اصلی این است که نکاتی را آشکار کنی که در نگاه سطحی و جداگانه به هر گزارش دیده نمی‌شوند: مغایرت‌های عددی هرچند کوچک بین دیدگاه‌ها یا بین فرم اول کارفرما و ادعای خود کارفرما در فرم‌های بعدی، جمله یا نکته‌ای که فقط یک رکن به آن اشاره کرده اما می‌تواند نشانه یک مسئله بزرگ‌تر باشد، و الگوهایی که فقط با کنار هم گذاشتن وضعیت چند حوزه یا جبهه کاری مختلف آشکار می‌شوند (نه هرکدام به‌تنهایی).

خروجی را دقیقاً و فقط به‌صورت یک شیء JSON معتبر برگردان — بدون Markdown، بدون بلوک کد، بدون هیچ متنی قبل یا بعد از آن. همه فیلدها الزامی‌اند؛ اگر آرایه‌ای موردی ندارد [] بگذار، هرگز فیلد را حذف نکن. دقیقاً با این ساختار:

{
  "overall": {
    "status_color": "🟢" یا "🟡" یا "🔴",
    "status_summary": "۲ تا ۳ جمله جمع‌بندی وضعیت واقعی پروژه، نه کلی‌گویی",
    "divergence_score": عددی صحیح بین ۰ تا ۱۰۰ — ۰ یعنی هر سه دیدگاه کاملاً همسو و بدون تناقض، ۱۰۰ یعنی تناقض‌های اساسی و غیرقابل‌توضیح بین دیدگاه‌ها؛ فقط بر اساس شواهد واقعی محاسبه کن نه حدس تصادفی,
    "divergence_note": "یک جمله کوتاه که توضیح دهد این عدد از کجا آمده"
  },
  "overlooked_insights": [
    { "insight": "نکته‌ای که به‌راحتی در نگاه اول دیده نمی‌شود", "evidence": "دقیقاً کدام بخش از داده‌ها این نکته را نشان می‌دهد", "why_it_matters": "چرا این نکته برای مدیریت مهم است" }
  ],
  "cross_perspective_contradictions": [
    { "topic": "موضوع تناقض", "کارفرما": "ادعا یا عدد کارفرما یا null اگر اشاره نکرده", "مشاور": "ادعا یا عدد مشاور یا null", "پیمانکار": "ادعا یا عدد پیمانکار یا null", "why_it_matters": "چرا این تناقض مهم است" }
  ],
  "problem_areas": [
    { "key": "دقیقاً یکی از این کلیدهای انگلیسی: engineering, procurement, construction, contract, finance, hse, quality (حوزه‌های X-Ray) یا row, pipe_supply, valve_equipment, welding, ndt, coating, lowering, backfilling, crossings, station_facility (جبهه‌های کاری)", "flagged_by": ["زیرمجموعه‌ای از کارفرما و/یا مشاور و/یا پیمانکار — هرکدام این حوزه/جبهه را زرد یا قرمز گزارش کرده"], "severity": "بحرانی" یا "زیاد" یا "متوسط", "synthesis": "چرا این حوزه/جبهه واقعاً مسئله‌ساز است" }
  ],
  "risk_register": [
    { "risk": "شرح ریسک", "source_org": "کارفرما" یا "مشاور" یا "پیمانکار", "level": "بحرانی" یا "زیاد" یا "متوسط" یا "کم", "current_action": "اقدام فعلی یا توصیه‌شده" }
  ],
  "quick_win_comparison": [
    { "organization": "کارفرما" یا "مشاور" یا "پیمانکار", "title": "عنوان پیشنهاد Quick Win آن رکن", "time_estimate_days": عدد تخمینی روز یا null, "impact_summary": "خلاصه اثر مورد انتظار", "recommended_rank": ۱ یا ۲ یا ۳ (۱ یعنی بیشترین اثر/کمترین زمان) }
  ],
  "selected_quick_win_assessment": "ارزیابی کوتاه از اینکه آیا Quick Win فعلاً برگزیده (در صورت وجود) هنوز بهترین انتخاب است؛ اگر هنوز چیزی انتخاب نشده null بگذار",
  "root_cause_analysis": { "primary_root_cause": "مهم‌ترین علت ریشه‌ای مشترک", "summary": "توضیح کوتاه" },
  "action_plan_30_days": [
    { "week": "هفته اول" یا "هفته دوم" یا "هفته سوم" یا "هفته چهارم", "action": "اقدام مشخص", "owner": "مسئول پیشنهادی" }
  ],
  "executive_decisions_needed": ["تصمیم مورد نیاز از مدیریت ارشد", "..."],
  "final_recommendation": "یک پاراگراف پایانی، مستقیم و قابل ارائه به مدیر اجرایی طرح"
}`;

    // deno-lint-ignore no-explicit-any
    let analysisJson: any;

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
          max_tokens: 4000,
          response_format: { type: "json_object" },
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
      const content = aiData.choices?.[0]?.message?.content;
      if (typeof content !== "string" || !content.trim()) {
        return jsonResponse({ error: "پاسخی از ChatGPT دریافت نشد." }, 502);
      }
      try {
        analysisJson = JSON.parse(content);
      } catch (_e) {
        return jsonResponse({ error: "پاسخ ChatGPT به‌صورت JSON معتبر نبود." }, 502);
      }
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
            generationConfig: { responseMimeType: "application/json" },
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
      // A response can legitimately carry more than one part (e.g. a
      // reasoning/thought part alongside the answer) — join every part
      // that actually is text instead of assuming parts[0] is it, so a
      // shape Google changes on us never hands the frontend a non-string.
      const parts = aiData.candidates?.[0]?.content?.parts;
      // deno-lint-ignore no-explicit-any
      const joinedText = Array.isArray(parts) ? parts.map((p: any) => (typeof p?.text === "string" ? p.text : "")).join("") : "";
      if (!joinedText.trim()) {
        return jsonResponse({ error: "پاسخی از Gemini دریافت نشد یا پاسخ توسط فیلتر محتوا مسدود شده است." }, 502);
      }
      try {
        analysisJson = JSON.parse(joinedText);
      } catch (_e) {
        return jsonResponse({ error: "پاسخ Gemini به‌صورت JSON معتبر نبود." }, 502);
      }
    }

    // Best-effort cache write — never let a caching failure hide an
    // otherwise-successful analysis from the caller.
    try {
      await supabase.from("ai_analyses").insert({
        project_name,
        provider: chosenProvider,
        analysis_json: analysisJson,
        source_data_at: newestSourceAt,
      });
    } catch (_e) {
      // ignore
    }

    return jsonResponse({ analysis: analysisJson, provider: chosenProvider, source: "live" });
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
