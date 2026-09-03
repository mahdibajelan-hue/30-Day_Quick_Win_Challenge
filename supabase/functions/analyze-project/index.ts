import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { project_name = "پروژه راهنما", provider = "gemini", force_refresh = false } = await req.json();

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);

    // ۱. بررسی کش دیتابیس
    if (!force_refresh) {
      const { data: cached } = await supabase
        .from("ai_analyses")
        .select("analysis_json")
        .eq("project_name", project_name)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (cached?.analysis_json) {
        return new Response(
          JSON.stringify({ analysis: JSON.parse(cached.analysis_json), source: "cache" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ۲. تعریف پرامپت سخت‌گیرانه برای JSON
    const systemInstruction = `تو یک مدیر ارشد PMO هستی. فقط و فقط یک شیء JSON معتبر طبق فرمت درخواستی تولید کن. هیچ متن اضافی یا توضیحات Markdown خارج از JSON ارسال نکن.`;

    const userPrompt = `پروژه: ${project_name}
    
یک گزارش تحلیلی کامل در قالب دقیق JSON زیر برگردان:
{
  "kpis": {
    "project_status_color": "RED",
    "status_title": "هشدار جدی تأخیر و توقف جبهه کاری",
    "divergence_score": 65,
    "schedule_variance_days": 62,
    "overall_progress_planned": 82,
    "overall_progress_actual": 76
  },
  "three_perspectives": [
    { "stakeholder": "کارفرما", "claimed_issue": "تأخیر در تأمین شیرآلات", "severity": "High" },
    { "stakeholder": "مشاور", "claimed_issue": "تأخیر در تأیید نقشه‌های As-built", "severity": "Critical" },
    { "stakeholder": "پیمانکار", "claimed_issue": "وجود معارضین ملکی", "severity": "Critical" }
  ],
  "root_cause_analysis": {
    "primary_root_cause": "عدم آزادسازی زمین و معطلی در گمرک",
    "analysis_summary": "بررسی ریشه‌ای نشان‌دهنده لزوم مداخله فوری مدیریت ارشد است."
  },
  "risk_assessment": {
    "top_bottleneck": "معارض ملکی کیلومتر ۳۲ الی ۳۴",
    "probability": 5,
    "impact": 5,
    "risk_score": 25
  },
  "quick_win": {
    "title": "رفع معارض ملکی قطعه ۳",
    "timeframe_days": 15,
    "owner": "مدیر پروژه کارفرما",
    "expected_impact": "کاهش ۲۵ روز تأخیر",
    "cost_impact": "بودجه مصوب"
  },
  "executive_decisions": [
    "تصویب بودجه تکمیلی تملک اراضی",
    "مکاتبه فوری با مدیریت گمرک"
  ],
  "action_plan_30_days": [
    { "week": "هفته اول", "action": "تکمیل مذاکرات ملکی", "owner": "کارفرما" },
    { "week": "هفته دوم", "action": "ترخیص کالا از گمرک", "owner": "پیمانکار/کارفرما" }
  ]
}`;

    let jsonString = "";

    // ۳. فراخوانی API با مدل رسمی gemini-3.6-flash
    if (provider === "gemini") {
      const apiKey = Deno.env.get("GEMINI_API_KEY");
      if (!apiKey) {
        throw new Error("کلید GEMINI_API_KEY در تنظیمات Supabase ست نشده است.");
      }

      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${apiKey}`;

      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemInstruction }] },
          contents: [{ parts: [{ text: userPrompt }] }],
          generationConfig: {
            response_mime_type: "application/json",
            temperature: 0.2
          }
        }),
      });

      const geminiData = await res.json();

      if (geminiData.error) {
        throw new Error(`خطای گوگل جمینای: ${geminiData.error.message}`);
      }

      if (!geminiData.candidates || geminiData.candidates.length === 0) {
        throw new Error("پاسخی از مدل Gemini دریافت نشد.");
      }

      jsonString = geminiData.candidates[0]?.content?.parts[0]?.text || "";
    } else {
      const apiKey = Deno.env.get("OPENAI_API_KEY");
      if (!apiKey) {
        throw new Error("کلید OPENAI_API_KEY در تنظیمات Supabase ست نشده است.");
      }

      const res = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          response_format: { type: "json_object" },
          temperature: 0.2,
          messages: [
            { role: "system", content: systemInstruction },
            { role: "user", content: userPrompt }
          ]
        })
      });

      const openaiData = await res.json();
      if (openaiData.error) {
        throw new Error(`خطای OpenAI: ${openaiData.error.message}`);
      }

      jsonString = openaiData.choices[0]?.message?.content || "";
    }

    // ۴. Pars و اعتبارسنجی خروجی
    const cleanJson = jsonString.replace(/```json/g, "").replace(/```/g, "").trim();
    if (!cleanJson) {
      throw new Error("خروجی هوش مصنوعی خالی است.");
    }

    const parsedData = JSON.parse(cleanJson);

    // ۵. ذخیره‌سازی در دیتابیس
    await supabase.from("ai_analyses").insert({
      project_name,
      provider,
      analysis_json: JSON.stringify(parsedData)
    });

    return new Response(
      JSON.stringify({ analysis: parsedData, source: "live" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
