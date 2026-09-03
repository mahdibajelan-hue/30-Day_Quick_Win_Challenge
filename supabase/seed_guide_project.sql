-- ============================================================
-- Seed script (NOT a migration — run manually, once, in the Supabase
-- SQL Editor, AFTER migration 014_guide_project_flag.sql has been
-- applied): creates/refreshes «پروژه راهنما», a fully-filled-out demo
-- project every real form in this app supports, written so a new
-- manager can read it and copy the pattern. It is flagged is_guide =
-- true, so index.html's loadOverview()/loadTrackingData() exclude it
-- from نمای کلی — everywhere else it behaves like a normal project.
--
-- Safe to re-run: it deletes any previous «پروژه راهنما» rows first,
-- then inserts a fresh, internally-consistent copy.
-- ============================================================

-- ---- 1. Make sure the project row exists and is flagged as guide ----
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM projects WHERE name = 'پروژه راهنما') THEN
        INSERT INTO projects (name, is_guide) VALUES ('پروژه راهنما', true);
    ELSE
        UPDATE projects SET is_guide = true WHERE name = 'پروژه راهنما';
    END IF;
END $$;

-- ---- 2. Clear any previous guide-project data (idempotent re-run) ----
DELETE FROM client_reports WHERE project_name = 'پروژه راهنما';
DELETE FROM check_ins WHERE project_name = 'پروژه راهنما';
DELETE FROM quick_win_decisions WHERE project_name = 'پروژه راهنما';
DELETE FROM quick_win_progress WHERE project_name = 'پروژه راهنما';

-- ---- 3. اطلاعات پایه پروژه (client_reports — one project-wide row) ----
INSERT INTO client_reports (
    user_id, project_name, plan_name, contract_number, contract_type, contract_type_other,
    contractor_name, consultant_name, client_pm_name, contractor_pm_name, consultant_pm_name,
    contract_initial_amount_rial, contract_initial_amount_eur, contract_current_amount_rial, contract_current_amount_eur,
    contract_start_date, contract_end_date, contract_duration_months, elapsed_months,
    progress_planned, progress_physical, progress_engineering, progress_procurement, progress_construction,
    milestone_name, milestone_planned_date, milestone_status, milestone_delay_days
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'طرح نمونه راهنما — خط لوله ۵۶ اینچ (جهت آموزش تکمیل فرم‌ها)', 'GDG6-DEMO-1403-001', 'EPC', NULL,
    'شرکت پیمانکاری سازه‌گستر پارس (نمونه)', 'مهندسین مشاور طرح و تحقیق انرژی (نمونه)', 'مهندس حسین رستمی', 'مهندس علی محمدی', 'مهندس سارا کریمی',
    8500, 12.5, 6200, 9.1,
    '2024-06-01', '2026-12-01', 30, 27,
    82, 76, 100, 88, 68,
    'تکمیل جوشکاری و تست هیدرواستاتیک قطعه ۳ از ۵', '2026-10-15', 'در معرض تأخیر', 10
);

-- ---- 4. اطلاعات تکمیلی (check_ins periodic — one row per organization) ----

-- کارفرما
INSERT INTO check_ins (
    user_id, project_name, organization, respondent, respondent_position, respondent_contact, qw_form_date,
    area_status, work_fronts, planned_progress, physical_progress, forecast_completion_date,
    hse_incident, hse_incident_note, issues, risks,
    q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
    senior_decision_needed, senior_decision_priority, one_thing_to_change, top_risk, risk_severity
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'کارفرما', 'حسین رستمی', 'کارشناس ارشد کنترل پروژه کارفرما', '021-88451200 / h.rostami@example.com', '2026-08-30',
    '{"engineering":{"status":"🟢 سبز","issue":"مدارک مهندسی طبق برنامه توسط مشاور تأیید و ابلاغ می‌شود."},"procurement":{"status":"🟡 زرد","issue":"ترخیص شیرآلات وارداتی از گمرک با تأخیر مواجه شده و نیازمند پیگیری فوق‌سازمانی است."},"construction":{"status":"🟡 زرد","issue":"پیشرفت اجرا ۶٪ عقب‌تر از برنامه، عمدتاً به دلیل معارض ملکی در کیلومتر ۳۲ الی ۳۴."},"contract":{"status":"🔴 قرمز","issue":"عدم توافق نهایی با ۷ مالک باقی‌مانده در مسیر خط لوله، ریسک ثبت Claim از سوی پیمانکار."},"finance":{"status":"🟡 زرد","issue":"تخصیص اعتبار دوره سوم با یک ماه تأخیر نسبت به برنامه مالی ابلاغی دریافت شد."},"hse":{"status":"🟢 سبز","issue":"بدون رویداد HSE قابل توجه در این دوره؛ صرفاً یک مورد Near-miss در کارگاه پیمانکار (شرح در بخش مربوطه)."},"quality":{"status":"🟢 سبز","issue":"نرخ ردی جوش در محدوده استاندارد و مطابق گزارش مشاور."}}'::jsonb,
    '{"row":{"status":"🔴 قرمز","issue":"۷ مورد معارض ملکی باقی‌مانده در کیلومتر ۳۲ الی ۳۴؛ در حال مذاکره برای پرداخت خسارت توافقی."},"pipe_supply":{"status":"🟢 سبز","issue":"تأمین لوله طبق برنامه و بدون مغایرت انجام شده است."},"valve_equipment":{"status":"🟡 زرد","issue":"شیرآلات وارداتی خط اصلی در گمرک بندرعباس با تأخیر ۳ هفته‌ای مواجه است."},"welding":{"status":"🟢 سبز","issue":"جوشکاری مطابق برنامه و با نرخ ردی قابل قبول پیش می‌رود."},"ndt":{"status":"🟢 سبز","issue":"تست‌های غیرمخرب همزمان با جوشکاری و بدون تأخیر انجام می‌شود."},"coating":{"status":"🟢 سبز","issue":"پوشش‌کاری در قطعات تحویلی مطابق مشخصات فنی است."},"lowering":{"status":"🟡 زرد","issue":"عملیات Lowering در قطعه ۳ به دلیل تأخیر رفع معارض ملکی متوقف مانده است."},"backfilling":{"status":"🟢 سبز","issue":"در قطعات تکمیل‌شده مطابق برنامه انجام شده است."},"crossings":{"status":"🟡 زرد","issue":"عبور از بزرگراه کیلومتر ۴۵ منتظر مجوز نهایی راهداری استان است."},"station_facility":{"status":"🟢 سبز","issue":"ساخت تأسیسات ایستگاه تقویت فشار طبق برنامه در حال پیشرفت است."}}'::jsonb,
    82, 76, '2027-02-01',
    false, NULL,
    '[{"description":"عدم توافق با ۷ مالک باقی‌مانده در مسیر خط لوله (کیلومتر ۳۲ الی ۳۴) و توقف جبهه کاری Lowering در این محدوده.","impact":["زمان","قرارداد","ریسک"],"severity":"بالا"},{"description":"تأخیر ۳ هفته‌ای ترخیص شیرآلات وارداتی خط اصلی از گمرک بندرعباس.","impact":["زمان","پیشرفت"],"severity":"متوسط"},{"description":"تأخیر یک‌ماهه در تخصیص اعتبار دوره سوم نسبت به برنامه مالی مصوب.","impact":["هزینه","زمان"],"severity":"متوسط"}]'::jsonb,
    '[{"risk":"ثبت ادعای خسارت (Claim) از سوی پیمانکار به دلیل تأخیر در تحویل جبهه کاری ناشی از معارض ملکی.","probability":"زیاد","impact":"زیاد","level":"بحرانی","current_action":"پیگیری فشرده پرداخت خسارت توافقی با مالکین باقی‌مانده و مکاتبه رسمی با مجری طرح جهت تسریع تخصیص بودجه."},{"risk":"تشدید تأخیر پیشرفت فیزیکی در صورت تداوم توقف عملیات Lowering قطعه ۳.","probability":"متوسط","impact":"زیاد","level":"زیاد","current_action":"برنامه‌ریزی جابه‌جایی موقت نیروی اجرایی به جبهه‌های دیگر تا رفع معارض."},{"risk":"تأخیر در بهره‌برداری ایستگاه تقویت فشار در صورت تأخیر بیشتر ترخیص شیرآلات.","probability":"کم","impact":"متوسط","level":"متوسط","current_action":"پیگیری روزانه وضعیت ترخیص از طریق واحد بازرگانی کارفرما."}]'::jsonb,
    'در صورت عدم رفع معارض ملکی طی ۳۰ روز آینده، احتمال ثبت ادعای خسارت رسمی از سوی پیمانکار و تشدید انحراف زمان‌بندی از ۶٪ فعلی به بیش از ۱۰٪ وجود دارد.',
    'عدم توافق نهایی با ۷ مالک باقی‌مانده در مسیر خط لوله (کیلومتر ۳۲ الی ۳۴) که مانع از تحویل جبهه کاری به پیمانکار شده است.',
    'عدم تخصیص به‌موقع اعتبار لازم برای پرداخت خسارت توافقی به مالکین در چارچوب برآورد اولیه بودجه تملک اراضی.',
    'تخصیص فوری بودجه تکمیلی تملک اراضی توسط مجری طرح و اختیار امضای توافق‌نامه مستقیم با مالکین توسط کارفرما.',
    'تصویب و تخصیص فوری بودجه تکمیلی برای پرداخت خسارت توافقی به ۷ مالک باقی‌مانده در مسیر خط لوله.',
    'فوری – کمتر از ۷ روز', 'تسریع در تخصیص اعتبار تملک اراضی همزمان با ابلاغ اولیه پروژه، نه پس از بروز توقف در جبهه کاری.',
    'ثبت ادعای خسارت (Claim) از سوی پیمانکار به دلیل تأخیر تحویل جبهه کاری.', 4
);

-- مشاور
INSERT INTO check_ins (
    user_id, project_name, organization, respondent, respondent_position, respondent_contact, qw_form_date,
    area_status, work_fronts, planned_progress, physical_progress, forecast_completion_date,
    hse_incident, hse_incident_note, issues, risks,
    q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
    senior_decision_needed, senior_decision_priority, one_thing_to_change, top_risk, risk_severity
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'مشاور', 'سارا کریمی', 'سرپرست کنترل پروژه و کیفیت مشاور', '021-88451300 / s.karimi@example.com', '2026-08-29',
    '{"engineering":{"status":"🟡 زرد","issue":"تأیید نهایی ۲ فقره نقشه As-built قطعه ۲ به دلیل عدم دریافت به‌موقع بازخورد کارفرما به تأخیر افتاده است."},"procurement":{"status":"🟢 سبز","issue":"بررسی فنی مدارک تأمین‌کنندگان طبق برنامه انجام می‌شود."},"construction":{"status":"🟡 زرد","issue":"نظارت بر اجرا در قطعه ۳ به دلیل توقف عملیات Lowering محدود شده است."},"contract":{"status":"🟢 سبز","issue":"موضوعی خارج از حیطه مشاور در این حوزه گزارش نشده است."},"finance":{"status":"🟢 سبز","issue":"موضوعی خارج از حیطه مشاور در این حوزه گزارش نشده است."},"hse":{"status":"🟢 سبز","issue":"بازرسی‌های HSE هفتگی بدون مورد قابل توجه انجام شد."},"quality":{"status":"🟡 زرد","issue":"نرخ ردی جوش در قطعه ۲ به‌طور موقت به دلیل تعویض یک اپراتور افزایش جزئی داشته که تحت کنترل است."}}'::jsonb,
    '{"row":{"status":"🔴 قرمز","issue":"عدم دسترسی به جبهه کاری قطعه ۳ امکان بازرسی تطبیقی نقشه با اجرا را محدود کرده است."},"pipe_supply":{"status":"🟢 سبز","issue":"گواهی‌های کیفی لوله‌های تحویلی بررسی و تأیید شده است."},"valve_equipment":{"status":"🟡 زرد","issue":"مدارک فنی شیرآلات وارداتی دریافت و در انتظار ورود فیزیکی جهت بازرسی نهایی است."},"welding":{"status":"🟢 سبز","issue":"کیفیت جوش مطابق WPS مصوب و در محدوده قابل قبول است."},"ndt":{"status":"🟡 زرد","issue":"نرخ ردی جوش قطعه ۲ موقتاً به ۳٪ رسیده؛ اصلاحیه آموزشی برای اپراتور جدید در دست اجراست."},"coating":{"status":"🟢 سبز","issue":"ضخامت‌سنجی پوشش در نمونه‌های تصادفی مطابق مشخصات است."},"lowering":{"status":"🔴 قرمز","issue":"متوقف در قطعه ۳ به دلیل معارض ملکی؛ امکان بازرسی و تأیید ادامه کار وجود ندارد."},"backfilling":{"status":"🟢 سبز","issue":"بازرسی تراکم خاک‌ریزی در قطعات تکمیل‌شده مطابق استاندارد بوده است."},"crossings":{"status":"🟡 زرد","issue":"طراحی نهایی عبور از بزرگراه کیلومتر ۴۵ در انتظار تأیید کارفرما برای ارسال به راهداری است."},"station_facility":{"status":"🟢 سبز","issue":"نظارت بر اجرای فونداسیون ایستگاه تقویت فشار مطابق نقشه در حال انجام است."}}'::jsonb,
    82, 75, '2027-02-15',
    false, NULL,
    '[{"description":"تأخیر در دریافت بازخورد کارفرما روی ۲ فقره نقشه As-built قطعه ۲.","impact":["زمان","کیفیت"],"severity":"متوسط"},{"description":"افزایش موقت نرخ ردی جوش قطعه ۲ به ۳٪ به دلیل تعویض اپراتور.","impact":["کیفیت","زمان"],"severity":"پایین"},{"description":"عدم امکان بازرسی میدانی قطعه ۳ به دلیل توقف عملیات ناشی از معارض ملکی.","impact":["کیفیت","پیشرفت"],"severity":"متوسط"}]'::jsonb,
    '[{"risk":"تثبیت نرخ ردی جوش بالای ۲٪ در صورت عدم تکمیل آموزش اپراتور جدید.","probability":"کم","impact":"متوسط","level":"متوسط","current_action":"برگزاری دوره آموزشی تکمیلی و بازرسی ۱۰۰٪ جوش‌های اپراتور جدید تا اثبات صلاحیت."},{"risk":"مغایرت نقشه As-built با اجرای واقعی در صورت تأخیر بیشتر تأیید کارفرما.","probability":"متوسط","impact":"متوسط","level":"متوسط","current_action":"پیگیری کتبی هفتگی از واحد مهندسی کارفرما برای تعیین‌تکلیف نقشه‌های معلق."},{"risk":"تأخیر تأیید طراحی عبور بزرگراه در صورت طولانی‌شدن هماهنگی با راهداری استان.","probability":"متوسط","impact":"کم","level":"کم","current_action":"ارسال زودهنگام مدارک فنی به کارفرما جهت کاهش زمان بررسی داخلی."}]'::jsonb,
    'در صورت عدم تعیین‌تکلیف نقشه‌های معلق قطعه ۲، ریسک مغایرت مستندات As-built با اجرای واقعی افزایش یافته و در مرحله تحویل موقت مشکل‌ساز خواهد شد.',
    'تأخیر در دریافت بازخورد و تأیید نهایی کارفرما روی مدارک مهندسی معلق (نقشه‌های As-built قطعه ۲).',
    'نبود جلسه منظم و زمان‌بندی‌شده بین واحد مهندسی مشاور و کارفرما برای بررسی و تأیید مدارک.',
    'تشکیل کمیته فنی مشترک با جلسات هفتگی ثابت برای تعیین‌تکلیف مدارک معلق ظرف حداکثر ۵ روز کاری.',
    'تصویب برگزاری جلسات هفتگی کمیته فنی مشترک کارفرما-مشاور با اختیار تصمیم‌گیری در همان جلسه.',
    'مهم – کمتر از ۱۴ روز', 'ایجاد یک کانال تأیید مدارک با زمان پاسخ‌گویی مشخص (SLA) به‌جای مکاتبات پراکنده فعلی.',
    'مغایرت احتمالی نقشه‌های As-built با اجرای واقعی به دلیل تأخیر تأیید.', 3
);

-- پیمانکار
INSERT INTO check_ins (
    user_id, project_name, organization, respondent, respondent_position, respondent_contact, qw_form_date,
    area_status, work_fronts, planned_progress, physical_progress, forecast_completion_date,
    hse_incident, hse_incident_note, issues, risks,
    q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
    senior_decision_needed, senior_decision_priority, one_thing_to_change, top_risk, risk_severity
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'پیمانکار', 'علی محمدی', 'مدیر اجرایی کارگاه', '0912-3456789 / a.mohammadi@example.com', '2026-08-31',
    '{"engineering":{"status":"🟢 سبز","issue":"نقشه‌های اجرایی به‌موقع از مشاور دریافت می‌شود."},"procurement":{"status":"🔴 قرمز","issue":"شیرآلات وارداتی خط اصلی ۳ هفته در گمرک بندرعباس متوقف مانده و مانع نصب در ایستگاه تقویت فشار است."},"construction":{"status":"🟡 زرد","issue":"عملیات Lowering قطعه ۳ به دلیل معارض ملکی کاملاً متوقف شده؛ نیروی اجرایی به قطعات دیگر منتقل شد."},"contract":{"status":"🟡 زرد","issue":"در حال بررسی حق تمدید مدت به دلیل تأخیرات غیرمرتبط با پیمانکار (معارض ملکی و ترخیص گمرکی)."},"finance":{"status":"🟢 سبز","issue":"صورت‌وضعیت‌های ارسالی طبق روال معمول در حال پرداخت است."},"hse":{"status":"🟡 زرد","issue":"یک مورد Near-miss (عدم استفاده موقت از کمربند ایمنی در کار در ارتفاع) ثبت و بلافاصله اصلاح شد؛ بدون آسیب."},"quality":{"status":"🟢 سبز","issue":"نرخ ردی جوش کارگاه در محدوده استاندارد و مورد تأیید مشاور است."}}'::jsonb,
    '{"row":{"status":"🔴 قرمز","issue":"عدم دسترسی به ۷ قطعه از مسیر در کیلومتر ۳۲ الی ۳۴ به دلیل معارض ملکی حل‌نشده."},"pipe_supply":{"status":"🟢 سبز","issue":"موجودی لوله در انبار کارگاه کافی و مطابق برنامه مصرف است."},"valve_equipment":{"status":"🔴 قرمز","issue":"شیرآلات اصلی ایستگاه تقویت فشار در گمرک متوقف؛ بدون آن نصب تجهیزات ایستگاه امکان‌پذیر نیست."},"welding":{"status":"🟢 سبز","issue":"۴ دستگاه جوش فعال؛ پیشرفت مطابق برنامه هفتگی."},"ndt":{"status":"🟢 سبز","issue":"تیم NDT هم‌زمان با جوشکاری فعالیت می‌کند و تأخیری ایجاد نکرده است."},"coating":{"status":"🟢 سبز","issue":"پوشش‌کاری با ظرفیت کامل و بدون توقف در حال انجام است."},"lowering":{"status":"🔴 قرمز","issue":"کاملاً متوقف در قطعه ۳؛ منتظر رفع معارض ملکی برای از سرگیری کار."},"backfilling":{"status":"🟢 سبز","issue":"در قطعات تکمیل‌شده با سرعت مناسب پیش می‌رود."},"crossings":{"status":"🟡 زرد","issue":"آماده‌سازی تجهیزات حفاری بزرگراه کیلومتر ۴۵ انجام شده؛ منتظر مجوز نهایی راهداری."},"station_facility":{"status":"🟡 زرد","issue":"فونداسیون ایستگاه تکمیل شده اما نصب تجهیزات به دلیل توقف شیرآلات در گمرک معطل مانده است."}}'::jsonb,
    82, 78, '2027-01-20',
    true, 'حین کار در ارتفاع روی پایه ایستگاه تقویت فشار، یک نفر از نیروی اجرایی به‌طور موقت کمربند ایمنی را رها کرد؛ سرکارگر بلافاصله کار را متوقف و فرد را از ارتفاع پایین آورد. آموزش مجدد HSE برای کل تیم همان روز برگزار شد. بدون آسیب یا خسارت.',
    '[{"description":"توقف کامل نصب تجهیزات ایستگاه تقویت فشار به دلیل ماندن ۳ هفته‌ای شیرآلات اصلی در گمرک بندرعباس.","impact":["زمان","پیشرفت"],"severity":"بالا"},{"description":"توقف عملیات Lowering قطعه ۳ به دلیل معارض ملکی حل‌نشده در کیلومتر ۳۲ الی ۳۴.","impact":["زمان","پیشرفت","قرارداد"],"severity":"بالا"},{"description":"یک مورد Near-miss HSE (عدم استفاده موقت از کمربند ایمنی) در کارگاه ایستگاه تقویت فشار.","impact":["ریسک"],"severity":"متوسط"}]'::jsonb,
    '[{"risk":"تأخیر در بهره‌برداری ایستگاه تقویت فشار در صورت تداوم توقف شیرآلات در گمرک.","probability":"زیاد","impact":"زیاد","level":"بحرانی","current_action":"مکاتبه رسمی با کارفرما برای صدور مجوز فوریتی ترخیص و پیگیری روزانه با گمرک بندرعباس."},{"risk":"تکرار حوادث Near-miss در کار در ارتفاع در صورت عدم تشدید نظارت HSE.","probability":"کم","impact":"زیاد","level":"متوسط","current_action":"افزایش بازرسی‌های سرزده HSE از یک به سه بار در هفته برای کارهای در ارتفاع."},{"risk":"درخواست تمدید مدت قرارداد در صورت تداوم توقف‌های خارج از کنترل پیمانکار.","probability":"متوسط","impact":"متوسط","level":"متوسط","current_action":"مستندسازی روزانه توقف‌ها جهت ارائه درخواست تمدید مستدل به کارفرما."}]'::jsonb,
    'در صورت تداوم توقف ترخیص شیرآلات، بهره‌برداری ایستگاه تقویت فشار حداقل یک ماه به تعویق می‌افتد و امکان تکمیل خط تا تاریخ قراردادی از بین می‌رود.',
    'توقف ۳ هفته‌ای شیرآلات اصلی ایستگاه تقویت فشار در گمرک بندرعباس.',
    'عدم صدور به‌موقع مجوز ترخیص فوریتی توسط مراجع ذی‌ربط برای کالای با اولویت پروژه‌های زیرساختی.',
    'درخواست و صدور مجوز ترخیص فوریتی توسط کارفرما/مجری طرح از طریق مکاتبه مستقیم با گمرک.',
    'صدور مجوز ترخیص فوریتی شیرآلات اصلی ایستگاه تقویت فشار از گمرک بندرعباس.',
    'فوری – کمتر از ۷ روز', 'پیش‌بینی و آغاز فرآیند ترخیص فوریتی کالاهای بحرانی از همان مرحله سفارش‌گذاری، نه پس از رسیدن کالا به گمرک.',
    'تأخیر بهره‌برداری ایستگاه تقویت فشار به دلیل توقف شیرآلات در گمرک.', 4
);

-- ---- 5. پیشنهاد Quick Win (check_ins QW rows — one row per organization) ----

-- کارفرما (this is the one selected as the winning Quick Win below)
INSERT INTO check_ins (
    user_id, project_name, organization, qw_form_date,
    qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
    quick_win_title, action_details, qw_rationale, tangible_result,
    plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date, plan_prerequisite, plan_decision_needed, plan_deliverable,
    kpi_name, kpi_current, kpi_target_30d,
    impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
    support_types, support_other_text, support_needed, counter_commitment,
    time_estimate, final_reflection
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'کارفرما', '2026-08-01',
    'Contract / Commercial', NULL, '["تأخیر زمانی","توقف جبهه کاری","ایجاد Claim"]'::jsonb, NULL,
    'تداوم بلاتکلیفی معارض ملکی، جبهه کاری Lowering قطعه ۳ را کاملاً متوقف نگه می‌دارد و زمینه ثبت ادعای خسارت (Claim) رسمی از سوی پیمانکار را فراهم می‌کند.',
    'رفع معارض ملکی کیلومتر ۳۲ الی ۳۴ از طریق پرداخت سریع خسارت توافقی',
    'تشکیل کارگروه فوری کارفرما-امور اراضی برای نهایی‌سازی مذاکره و پرداخت خسارت توافقی به ۷ مالک باقی‌مانده، با استفاده از تخصیص بودجه اضطراری تملک اراضی.',
    'این مسیر تنها گلوگاه فعال جلوگیری از پیشرفت فیزیکی قطعه ۳ است؛ رفع آن بدون نیاز به تغییر طراحی یا قرارداد، صرفاً با تسریع فرآیند اداری پرداخت امکان‌پذیر است.',
    'آزادسازی کامل جبهه کاری Lowering قطعه ۳ ظرف ۳۰ روز و از سرگیری عملیات اجرایی در این محدوده.',
    'نهایی‌سازی و پرداخت توافق‌نامه خسارت با ۷ مالک باقی‌مانده', 'مهندس حسین رستمی — کارشناس ارشد کنترل پروژه کارفرما', 'واحد امور اراضی کارفرما، واحد مالی، دفتر حقوقی مجری طرح',
    '2026-08-05', '2026-09-04', 'تخصیص بودجه تکمیلی تملک اراضی توسط مجری طرح', 'تصویب تخصیص بودجه اضطراری تملک اراضی', 'توافق‌نامه‌های امضاشده با ۷ مالک به‌همراه رسید پرداخت خسارت',
    'تعداد مالکین دارای توافق نهایی', '۰ از ۷ مالک', '۷ از ۷ مالک',
    25, 5, 4000000000, 1, 7, 'جبهه کاری Lowering قطعه ۳ (کیلومتر ۳۲ الی ۳۴)', 'کاهش ریسک ثبت ادعای خسارت (Claim) از سوی پیمانکار',
    '["تأمین منابع مالی","تصمیم مجری طرح"]'::jsonb, NULL,
    'تخصیص فوری بودجه تکمیلی تملک اراضی توسط مجری طرح و اختیار امضای مستقیم توافق‌نامه با مالکین توسط کارفرما.',
    'در صورت تخصیص بودجه ظرف یک هفته، کارفرما متعهد می‌شود ظرف ۳۰ روز کلیه توافقات را نهایی و جبهه کاری کیلومتر ۳۲ الی ۳۴ را به‌طور کامل و مستند به پیمانکار تحویل دهد.',
    '۱۵ تا ۳۰ روز', 'با رفع این معارض، پیشرفت فیزیکی قطعه ۳ می‌تواند ظرف یک ماه به‌طور محسوس به روند برنامه‌ای بازگردد و ریسک اصلی پروژه در این دوره برطرف می‌شود.'
);

-- مشاور
INSERT INTO check_ins (
    user_id, project_name, organization, qw_form_date,
    qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
    quick_win_title, action_details, qw_rationale, tangible_result,
    plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date, plan_prerequisite, plan_decision_needed, plan_deliverable,
    kpi_name, kpi_current, kpi_target_30d,
    impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
    support_types, support_other_text, support_needed, counter_commitment,
    time_estimate, final_reflection
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'مشاور', '2026-08-27',
    'Engineering', NULL, '["تأخیر زمانی","کاهش پیشرفت","افت کیفیت"]'::jsonb, NULL,
    'تأخیر مستمر در تأیید مدارک مهندسی، ریسک مغایرت مستندات As-built با اجرای واقعی را افزایش داده و در مرحله تحویل موقت به مشکل تبدیل خواهد شد.',
    'کاهش زمان تأیید مدارک مهندسی از طریق تشکیل کمیته فنی مشترک هفتگی',
    'برگزاری جلسه ثابت هفتگی (هر سه‌شنبه) با حضور نمایندگان تام‌الاختیار مهندسی کارفرما و مشاور برای بررسی و تعیین‌تکلیف قطعی مدارک معلق در همان جلسه.',
    'علت اصلی تأخیر، نبود کانال تصمیم‌گیری منظم است، نه پیچیدگی فنی مدارک؛ راه‌حل سازمانی و بدون هزینه است.',
    'کاهش زمان میانگین تأیید مدارک از ۱۸ روز فعلی به کمتر از ۵ روز کاری.',
    'تشکیل و برگزاری منظم کمیته فنی مشترک هفتگی', 'مهندس سارا کریمی — سرپرست کنترل پروژه و کیفیت مشاور', 'واحد مهندسی کارفرما، واحد مهندسی مشاور',
    '2026-08-28', '2026-09-10', 'ابلاغ نماینده تام‌الاختیار مهندسی از سوی کارفرما', 'تعیین نماینده ثابت کارفرما با اختیار تأیید مدارک', 'صورت‌جلسه هفتگی به‌همراه فهرست مدارک تعیین‌تکلیف‌شده',
    'میانگین زمان تأیید مدارک (روز)', '۱۸ روز', 'کمتر از ۵ روز',
    10, 2, NULL, 2, 6, 'بدون آزادسازی جبهه کاری مستقیم؛ اثر عمدتاً بر کاهش زمان انتظار مهندسی است.', 'افزایش رضایت پیمانکار از روند تعیین‌تکلیف مدارک فنی',
    '["تصمیم مدیریت طرح","هماهنگی بین واحدها"]'::jsonb, NULL,
    'تصویب تشکیل کمیته فنی مشترک هفتگی توسط مدیریت طرح و الزام واحد مهندسی کارفرما به حضور با اختیار تصمیم‌گیری.',
    'مشاور متعهد می‌شود دستور جلسه و مستندات فنی هر جلسه را حداقل ۴۸ ساعت زودتر ارسال کند تا کارفرما فرصت بررسی کافی داشته باشد و جلسات به بیش از ۴۵ دقیقه نینجامد.',
    '۷ تا ۱۴ روز', 'این اقدام یک تغییر رویه ساده و کم‌هزینه است که در صورت تثبیت، در تمام مراحل باقی‌مانده پروژه از تکرار همین گلوگاه جلوگیری می‌کند.'
);

-- پیمانکار
INSERT INTO check_ins (
    user_id, project_name, organization, qw_form_date,
    qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
    quick_win_title, action_details, qw_rationale, tangible_result,
    plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date, plan_prerequisite, plan_decision_needed, plan_deliverable,
    kpi_name, kpi_current, kpi_target_30d,
    impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
    support_types, support_other_text, support_needed, counter_commitment,
    time_estimate, final_reflection
) VALUES (
    (SELECT user_id FROM app_users WHERE role = 'admin' LIMIT 1),
    'پروژه راهنما', 'پیمانکار', '2026-08-25',
    'Procurement', NULL, '["تأخیر زمانی","توقف جبهه کاری","افزایش هزینه"]'::jsonb, NULL,
    'تا زمان ترخیص شیرآلات اصلی، نصب تجهیزات ایستگاه تقویت فشار کاملاً متوقف است و نیروی نصب‌شده بدون کار مفید در کارگاه مستقر می‌ماند.',
    'تسریع ترخیص شیرآلات وارداتی ایستگاه تقویت فشار از گمرک بندرعباس از طریق مجوز فوریتی',
    'درخواست صدور مجوز ترخیص فوریتی کالای پروژه‌های زیرساختی از طریق مکاتبه مستقیم کارفرما/مجری طرح با گمرک بندرعباس و پیگیری حضوری روزانه.',
    'کالا فیزیکاً در گمرک موجود است؛ تأخیر صرفاً اداری است و با اولویت‌بندی رسمی قابل رفع در کمتر از دو هفته است.',
    'ترخیص و تحویل شیرآلات به کارگاه ظرف حداکثر ۱۴ روز و از سرگیری نصب تجهیزات ایستگاه.',
    'پیگیری فشرده ترخیص فوریتی با حضور نماینده مشترک کارفرما و پیمانکار در گمرک', 'مهندس علی محمدی — مدیر اجرایی کارگاه', 'واحد بازرگانی کارفرما، دفتر گمرکی پیمانکار، مجری طرح',
    '2026-08-26', '2026-09-20', 'صدور نامه اولویت‌بندی رسمی از مجری طرح خطاب به گمرک', 'صدور نامه اولویت فوریتی ترخیص توسط مجری طرح', 'شیرآلات ترخیص‌شده و تحویلی به انبار کارگاه',
    'روزهای توقف نصب تجهیزات ایستگاه', '۲۱ روز', '۰ روز (نصب از سر گرفته شود)',
    20, 4, 1500000000, 1, NULL, 'نصب تجهیزات ایستگاه تقویت فشار', 'جلوگیری از هزینه بلااستفاده ماندن نیروی نصب مستقر در کارگاه',
    '["رفع محدودیت اجرایی","تصمیم مجری طرح"]'::jsonb, NULL,
    'صدور نامه رسمی اولویت‌بندی فوریتی ترخیص گمرکی توسط مجری طرح خطاب به گمرک بندرعباس.',
    'پیمانکار متعهد می‌شود بلافاصله پس از ترخیص، ظرف ۳۰ روز نصب کامل تجهیزات ایستگاه تقویت فشار را به پایان برساند و نیروی مستقر را بدون فوت وقت به کار بگیرد.',
    '۱۵ تا ۳۰ روز', 'رفع این محدودیت گلوگاه اصلی بهره‌برداری ایستگاه تقویت فشار را برطرف کرده و مسیر بحرانی پروژه را کوتاه‌تر می‌کند.'
);

-- ---- 6. انتخاب Quick Win (quick_win_decisions — کارفرما's proposal wins) ----
INSERT INTO quick_win_decisions (
    project_name, selected_organization, selected_title, selected_action, selected_result,
    selected_support, selected_counter_commitment,
    impact_score, feasibility_score, cost_score, priority_score, rationale, decided_by, target_date, created_at
) VALUES (
    'پروژه راهنما', 'کارفرما', 'رفع معارض ملکی کیلومتر ۳۲ الی ۳۴ از طریق پرداخت سریع خسارت توافقی',
    'تشکیل کارگروه فوری کارفرما-امور اراضی برای نهایی‌سازی مذاکره و پرداخت خسارت توافقی به ۷ مالک باقی‌مانده، با استفاده از تخصیص بودجه اضطراری تملک اراضی.',
    'آزادسازی کامل جبهه کاری Lowering قطعه ۳ ظرف ۳۰ روز و از سرگیری عملیات اجرایی در این محدوده.',
    'تخصیص فوری بودجه تکمیلی تملک اراضی توسط مجری طرح و اختیار امضای مستقیم توافق‌نامه با مالکین توسط کارفرما.',
    'در صورت تخصیص بودجه ظرف یک هفته، کارفرما متعهد می‌شود ظرف ۳۰ روز کلیه توافقات را نهایی و جبهه کاری کیلومتر ۳۲ الی ۳۴ را به‌طور کامل و مستند به پیمانکار تحویل دهد.',
    5, 4, 4, 4.45,
    'امتیاز نهایی ۴.۴۵/۵ — تصمیم: Quick Win منتخب. این پیشنهاد به دلیل تأثیر مستقیم بر مسیر بحرانی پروژه (رفع تنها گلوگاه فعال جبهه کاری) و امکان اجرای سریع بدون تغییر قراردادی، به‌عنوان Quick Win این دوره انتخاب شد.',
    (SELECT email FROM app_users WHERE role = 'admin' LIMIT 1),
    '2026-09-04', '2026-08-06'
);

-- ---- 7. پیگیری اجرا (quick_win_progress — progress log for the winning Quick Win) ----
INSERT INTO quick_win_progress (project_name, status, progress_percent, note, reported_by, created_at) VALUES
    ('پروژه راهنما', 'در حال انجام', 20, 'مذاکره با ۴ مالک از ۷ مالک باقی‌مانده انجام و توافق اولیه حاصل شد؛ در انتظار تخصیص بودجه برای پرداخت.', (SELECT email FROM app_users WHERE role = 'admin' LIMIT 1), '2026-08-12'),
    ('پروژه راهنما', 'در حال انجام', 55, 'بودجه تکمیلی تخصیص یافت؛ توافق با ۶ مالک از ۷ نهایی و در مراحل اداری پرداخت است.', (SELECT email FROM app_users WHERE role = 'admin' LIMIT 1), '2026-08-22'),
    ('پروژه راهنما', 'در حال انجام', 80, 'خسارت توافقی به ۶ مالک پرداخت و جبهه کاری مربوطه تحویل پیمانکار شد؛ مذاکره با آخرین مالک باقی‌مانده ادامه دارد.', (SELECT email FROM app_users WHERE role = 'admin' LIMIT 1), '2026-09-01');
