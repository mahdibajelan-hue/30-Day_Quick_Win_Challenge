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

    // 1. بررسی کش در دیتابیس
    if (!force_refresh) {
      const { data: cached } = await supabase
        .from("ai_analyses")
        .select("analysis_json")
        .eq("project_name", project_name)
        .order("created_at", { ascending: false })
        .limit(1)
        .single();

      if (cached?.analysis_json) {
        return new Response(
          JSON.stringify({ analysis: JSON.parse(cached.analysis_json), source: "cache" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // 2. پرامپت سخت‌گیرانه برای تولید STRICT JSON
    const systemInstruction = `تو یک مدیر ارشد PMO و تحلیل‌گر داده پروژه‌های عمرانی/صنعتی هستی.
وظیفه تو تحلیل گزارش‌های سه‌گانه (کارفرما، مشاور، پیمانکار) و تولید یک خروجی JSON کاملاً ساختاریافته است.
تو باید حتماً خروجی را فقط به صورت JSON معتبر برگردانی. هیچ متن اضافی، توضیح یا کد Markdown نباید خارج از ساختار JSON وجود داشته باشد.`;

    const userPrompt = `پروژه مورد بررسی: ${project_name}

اطلاعات گزارش‌های ۳ طرف را تحلیل کن و دقیقا ساختار JSON زیر را پر کن:

{
  "kpis": {
    "project_status_color": "RED", // یکی از مقادیر: RED یا YELLOW یا GREEN
    "status_title": "عنوان کوتاه وضعیت پروژه (مثلاً: هشدار جدی تأخیر و توقف جبهه کاری)",
    "divergence_score": 65, // عدد بین 0 تا 100 میزان اختلاف گزارش‌ها
    "schedule_variance_days": 62, // عدد انحراف زمانی به روز
    "overall_progress_planned": 82, // درصد برنامه‌ای
    "overall_progress_actual": 76 // درصد واقعی
  },
  "three_perspectives": [
    {
      "stakeholder": "کارفرما",
      "claimed_issue": "تأخیر در تأمین شیرآلات و عقب‌ماندگی از برنامه",
      "severity": "High" // Critical, High, Medium, Low
    },
    {
      "stakeholder": "مشاور",
      "claimed_issue": "عدم تأیید نقشه‌های As-built و تأخیر در جبهه کاری قطعه ۳",
      "severity": "Critical"
    },
    {
      "stakeholder": "پیمانکار",
      "claimed_issue": "توقف عملیات به دلیل وجود معارضین ملکی در کیلومتر ۳۲ الی ۳۴",
      "severity": "Critical"
    }
  ],
  "root_cause_analysis": {
    "primary_root_cause": "علت اصلی و ریشه‌ای تمامی مشکلات (مثلاً: عدم آزادسازی زمین و توقف گمرک)",
    "analysis_summary": "خلاصه دو جمله‌ای از تحلیل ریشه‌ای پایش پروژه"
  },
  "risk_assessment": {
    "top_bottleneck": "بحرانی‌ترین گلوگاه فعلی (مثلاً: معارض ملکی کیلومتر ۳۲ الی ۳۴)",
    "probability": 5, // 1 تا 5
    "impact": 5, // 1 تا 5
    "risk_score": 25
  },
  "quick_win": {
    "title": "عنوان پیشنهاد Quick Win اصلی",
    "timeframe_days": 15,
    "owner": "مدیر پروژه کارفرما",
    "expected_impact": "میزان تأثیرگذاری (مثلاً کاهش ۲۵ روز تأخیر و رفع ریسک حقوقی)",
    "cost_impact": "کم‌هزینه / بودجه مصوب"
  },
  "executive_decisions": [
    "تصمیم فوری ۱ برای C-Level",
    "تصمیم فوری ۲ برای C-Level"
  ],
  "action_plan_30_days": [
    { "week": "هفته اول", "action": "شرح اقدام اول", "owner": "مسئول" },
    { "week": "هفته دوم", "action": "شرح اقدام دوم", "owner": "مسئول" },
    { "week": "هفته سوم", "action": "شرح اقدام سوم", "owner": "مسئول" },
    { "week": "هفته چهارم", "action": "شرح اقدام چهارم", "owner": "مسئول" }
  ]
}`;

    let jsonString = "";

    // 3. فراخوانی Gemini با فعال‌سازی response_mime_type: "application/json"
    if (provider === "gemini") {
      const apiKey = Deno.env.get("GEMINI_API_KEY");
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: `${systemInstruction}\n\n${userPrompt}` }] }],
          generationConfig: {
            response_mime_type: "application/json" // اجبار هوش مصنوعی به تولید JSON
          }
        }),
      });

      const geminiData = await res.json();
      jsonString = geminiData.candidates[0].content.parts[0].text;
    } else {
      // فراخوانی OpenAI با response_format json_object
      const apiKey = Deno.env.get("OPENAI_API_KEY");
      const res = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: systemInstruction },
            { role: "user", content: userPrompt }
          ]
        })
      });

      const openaiData = await res.json();
      jsonString = openaiData.choices[0].message.content;
    }

    // پاک‌سازی احتمالی متون اضافی
    const cleanJson = jsonString.replace(/```json/g, "").replace(/```/g, "").trim();
    const parsedData = JSON.parse(cleanJson);

    // 4. ذخیره در دیتابیس
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
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
