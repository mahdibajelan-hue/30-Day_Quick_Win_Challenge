-- ============================================================
-- Demo/test data: one fully-populated project, all three
-- organizations, every field filled in with realistic content —
-- meant to give the AI analysis and both report pages (per-project
-- AI report + portfolio Executive Report) rich, non-empty material
-- to work with.
--
-- Run this in the Supabase SQL Editor AFTER 002_expanded_reports.sql
-- and 003_scope_visibility_to_own_project.sql have both been applied.
-- Requires at least one admin already set up in app_users (role='admin')
-- — every row below is attributed to that admin's account, the same way
-- the in-app "پیش‌نمایش فرم‌ها" admin picker attributes its submissions.
--
-- The project is named with a "(نمونه آزمایشی)" suffix specifically so
-- it's unmistakably demo data next to your real projects. To remove it
-- later, see the commented-out cleanup block at the very end of this file.
-- ============================================================

do $$
declare
    v_project text := 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
    v_user_id uuid;
    v_email text;
    v_ts_client timestamptz := '2026-08-25 09:00:00+00';
    v_ts_consultant timestamptz := '2026-08-26 10:00:00+00';
    v_ts_contractor timestamptz := '2026-08-27 11:00:00+00';
begin
    select user_id, email into v_user_id, v_email from app_users where role = 'admin' limit 1;
    if v_user_id is null then
        raise exception 'No admin found in app_users — set up an admin first, then re-run this script.';
    end if;

    -- 1. Project
    insert into projects (name)
    select v_project
    where not exists (select 1 from projects where name = v_project);

    -- 2. Client (کارفرما) check-in
    insert into check_ins (
        created_at, user_id, project_name, organization,
        respondent, respondent_position, respondent_contact, qw_form_date,
        area_status, work_fronts,
        planned_progress, physical_progress, financial_progress, forecast_completion_date,
        manpower_count, weld_reject_rate, hse_incident, hse_incident_note,
        issues, risks,
        q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
        senior_decision_needed, senior_decision_priority, one_thing_to_change,
        top_risk, risk_severity,
        qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
        quick_win_title, action_details, qw_rationale, tangible_result,
        plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date,
        plan_prerequisite, plan_decision_needed, plan_deliverable,
        kpi_name, kpi_current, kpi_target_30d,
        impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
        support_types, support_other_text, support_needed, time_estimate, final_reflection
    ) values (
        v_ts_client, v_user_id, v_project, 'کارفرما',
        'مهندس علی رضایی', 'مدیر پروژه کارفرما', 'a.rezaei@nigc.ir', '2026-08-25',
        '{"engineering":{"status":"🟢 سبز","issue":"نقشه‌های ایزومتریک نهایی و ابلاغ شده"},"procurement":{"status":"🟡 زرد","issue":"تاخیر سه‌هفته‌ای در ترخیص شیرآلات وارداتی"},"construction":{"status":"🟡 زرد","issue":"کمبود نیروی جوشکار ماهر در جبهه ۲"},"contract":{"status":"🟢 سبز","issue":"بدون اختلاف قراردادی باز"},"finance":{"status":"🔴 قرمز","issue":"صورت‌وضعیت دوره ۱۴ پیمانکار ۴۵ روز معوق"},"hse":{"status":"🟡 زرد","issue":"یک مورد نزدیک به حادثه در جبهه حفاری"},"quality":{"status":"🟢 سبز","issue":"نرخ قبولی تست‌های NDT بالای ۹۸ درصد"}}'::jsonb,
        '{"row":{"status":"🟢 سبز","issue":"تحویل کامل زمین به پیمانکار"},"pipe_supply":{"status":"🟢 سبز","issue":"تحویل کامل لوله API 5L X70"},"valve_equipment":{"status":"🔴 قرمز","issue":"تاخیر گمرکی شیرآلات ۳۰ اینچ ساخت اروپا"},"welding":{"status":"🟡 زرد","issue":"کمبود ۱۲ جوشکار واجد شرایط"},"ndt":{"status":"🟢 سبز","issue":"بدون توقف در صف تست"},"coating":{"status":"🟢 سبز","issue":"کارکرد عادی"},"lowering":{"status":"🟡 زرد","issue":"تاخیر به دلیل انتظار برای جوشکاری"},"backfilling":{"status":"🟢 سبز","issue":"مطابق برنامه"},"crossings":{"status":"🔴 قرمز","issue":"عبور از رودخانه قزل‌اوزن نیازمند مجوز محیط‌زیست معطل‌مانده"},"station_facility":{"status":"🟡 زرد","issue":"تاخیر در تامین تجهیزات ایستگاه تقلیل فشار اردبیل"}}'::jsonb,
        62, 54, 58, '2027-03-20',
        340, 3.2, true, 'نزدیک به حادثه در جبهه حفاری کیلومتر ۴۵ - سقوط ابزار از ارتفاع، بدون مصدوم، گزارش HSE ثبت و اقدام اصلاحی ابلاغ شد',
        '[{"description":"تاخیر ترخیص گمرکی شیرآلات ۳۰ اینچ","impact":["زمان","پیشرفت"],"severity":"بالا"},{"description":"معوقات صورت‌وضعیت پیمانکار","impact":["هزینه","قرارداد"],"severity":"بالا"},{"description":"کمبود نیروی جوشکار ماهر","impact":["زمان","کیفیت"],"severity":"متوسط"}]'::jsonb,
        '[{"risk":"تاخیر بیشتر در صدور مجوز عبور از رودخانه قزل‌اوزن","probability":"زیاد","impact":"زیاد","level":"بحرانی","current_action":"پیگیری روزانه با اداره محیط‌زیست استان"},{"risk":"کاهش بیشتر نقدینگی پیمانکار به دلیل تاخیر پرداخت","probability":"متوسط","impact":"زیاد","level":"زیاد","current_action":"درخواست تسریع تایید صورت‌وضعیت به امور مالی"},{"risk":"ورود فصل بارندگی و توقف عملیات خاکی","probability":"متوسط","impact":"متوسط","level":"متوسط","current_action":"بازنگری برنامه زمان‌بندی جبهه‌های خاکی"}]'::jsonb,
        'در صورت عدم صدور مجوز عبور از رودخانه طی این ماه، جبهه اجرایی حدود شش کیلومتر برای حداقل دو ماه متوقف و تکمیل طرح به تعویق می‌افتد',
        'تاخیر صدور مجوز عبور از رودخانه قزل‌اوزن',
        'کندی فرآیند بررسی زیست‌محیطی در اداره کل محیط‌زیست استان و عدم تکمیل مدارک تکمیلی درخواستی',
        'برگزاری جلسه مشترک سطح مدیران با اداره کل محیط‌زیست و تسریع تکمیل مدارک باقی‌مانده طی یک هفته',
        'درخواست مکاتبه رسمی مدیرعامل با استانداری برای تسریع صدور مجوز زیست‌محیطی',
        'فوری – کمتر از ۷ روز', 'سرعت‌بخشی به فرآیند صدور مجوزهای زیست‌محیطی از ابتدای پروژه',
        'تاخیر مجوز رودخانه و اثر زنجیره‌ای آن بر جبهه‌های پایین‌دست', 5,
        'Management / Decision Making', null, '["تأخیر زمانی","توقف جبهه کاری","تأخیر در بهره‌برداری"]'::jsonb, null,
        'عدم اخذ مجوز طی دو هفته آینده باعث توقف کامل جبهه عبور از رودخانه و تاخیر زنجیره‌ای در جبهه‌های پایین‌دست خواهد شد',
        'اخذ مجوز موقت عبور از رودخانه قزل‌اوزن طی ۳۰ روز',
        'برگزاری جلسه فوری با مدیرکل محیط‌زیست استان، تکمیل و ارسال مدارک تکمیلی درخواستی ظرف پنج روز کاری، و پیگیری روزانه تا صدور مجوز موقت اجرا',
        'این گلوگاه به‌تنهایی می‌تواند بیش از دو ماه به کل زمان‌بندی طرح اضافه کند و رفع آن کمترین هزینه و بیشترین اثر زمانی را در بین همه اقدامات ممکن دارد',
        'صدور مجوز موقت و از سرگیری عملیات عبور از رودخانه ظرف ۳۰ روز',
        'پیگیری متمرکز اخذ مجوز محیط‌زیست', 'مدیر پروژه کارفرما - مهندس علی رضایی', 'واحد HSE کارفرما، امور حقوقی، پیمانکار', '2026-08-25', '2026-09-24',
        'تکمیل نقشه‌های فنی روش عبور توسط مشاور', 'تایید مدیرعامل برای مکاتبه رسمی با استانداری', 'مجوز موقت عبور از رودخانه (نامه رسمی اداره محیط‌زیست)',
        'روزهای معطلی جبهه عبور از رودخانه', '۲۸ روز معطلی تجمعی', 'صفر روز معطلی و از سرگیری کامل عملیات',
        45, 4, 80000000000, 1, 3, 'جبهه عبور از رودخانه به‌همراه دو جبهه پایین‌دست', 'کاهش ریسک جریمه تاخیر قراردادی',
        '["تصمیم مدیرعامل","هماهنگی بین واحدها"]'::jsonb, null, 'مکاتبه رسمی مدیرعامل با استانداری و پیگیری حقوقی موازی', '۱۵ تا ۳۰ روز',
        'رفع این یک گلوگاه می‌تواند طرح را از حالت پرخطر به مسیر بازیابی برنامه بازگرداند'
    );

    -- 3. Consultant (مشاور) check-in
    insert into check_ins (
        created_at, user_id, project_name, organization,
        respondent, respondent_position, respondent_contact, qw_form_date,
        area_status, work_fronts,
        planned_progress, physical_progress, financial_progress, forecast_completion_date,
        manpower_count, weld_reject_rate, hse_incident, hse_incident_note,
        issues, risks,
        q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
        senior_decision_needed, senior_decision_priority, one_thing_to_change,
        top_risk, risk_severity,
        qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
        quick_win_title, action_details, qw_rationale, tangible_result,
        plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date,
        plan_prerequisite, plan_decision_needed, plan_deliverable,
        kpi_name, kpi_current, kpi_target_30d,
        impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
        support_types, support_other_text, support_needed, time_estimate, final_reflection
    ) values (
        v_ts_consultant, v_user_id, v_project, 'مشاور',
        'دکتر سارا احمدی', 'مدیر پروژه مشاور - نظارت کارگاهی', 's.ahmadi@consultgroup.ir', '2026-08-26',
        '{"engineering":{"status":"🟢 سبز","issue":"بازنگری نقشه‌های As-Built تا کیلومتر ۳۰ تکمیل شد"},"procurement":{"status":"🟡 زرد","issue":"عدم تطابق برخی گواهی‌های کیفی شیرآلات با مشخصات فنی"},"construction":{"status":"🔴 قرمز","issue":"نرخ ردی جوش بالاتر از حد مجاز در جبهه ۲"},"contract":{"status":"🟢 سبز","issue":"بدون موضوع باز"},"finance":{"status":"🟡 زرد","issue":"تاخیر تایید صورت‌وضعیت به دلیل نقص مدارک فنی پیمانکار"},"hse":{"status":"🟡 زرد","issue":"عدم استفاده کامل از تجهیزات حفاظت فردی در برخی جبهه‌ها"},"quality":{"status":"🔴 قرمز","issue":"نرخ ردی جوش شش درصد - بالاتر از حد مجاز قراردادی چهار درصد"}}'::jsonb,
        '{"row":{"status":"🟢 سبز","issue":"بدون مسئله"},"pipe_supply":{"status":"🟢 سبز","issue":"کیفیت لوله‌ها مطابق مشخصات"},"valve_equipment":{"status":"🟡 زرد","issue":"برخی گواهی‌های کیفی نیازمند بازبینی"},"welding":{"status":"🔴 قرمز","issue":"نرخ ردی رادیوگرافی شش درصد در جبهه ۲، بالای حد مجاز"},"ndt":{"status":"🟡 زرد","issue":"افزایش حجم تست‌های مجدد به دلیل ردی بالا"},"coating":{"status":"🟢 سبز","issue":"کیفیت پوشش مطلوب"},"lowering":{"status":"🟡 زرد","issue":"معطلی به دلیل انتظار تایید مجدد جوش"},"backfilling":{"status":"🟢 سبز","issue":"مطابق برنامه"},"crossings":{"status":"🔴 قرمز","issue":"توقف کامل به دلیل عدم مجوز محیط‌زیست"},"station_facility":{"status":"🟢 سبز","issue":"طراحی نهایی ایستگاه تقلیل فشار تایید شد"}}'::jsonb,
        62, 47, 50, '2027-05-10',
        355, 6.0, false, null,
        '[{"description":"نرخ ردی جوش بالاتر از حد مجاز قراردادی","impact":["کیفیت","زمان","هزینه"],"severity":"بالا"},{"description":"عدم تطابق برخی گواهی‌های کیفی شیرآلات","impact":["کیفیت","قرارداد"],"severity":"متوسط"},{"description":"استفاده ناقص از تجهیزات حفاظت فردی","impact":["ریسک"],"severity":"متوسط"}]'::jsonb,
        '[{"risk":"ادامه روند ردی بالای جوش تا پایان جبهه ۲","probability":"زیاد","impact":"زیاد","level":"بحرانی","current_action":"الزام بازآموزی جوشکاران و افزایش نظارت WPS"},{"risk":"رد گواهی کیفی شیرآلات توسط بازرس شخص ثالث","probability":"متوسط","impact":"زیاد","level":"زیاد","current_action":"استعلام مجدد از سازنده اروپایی"},{"risk":"کاهش ایمنی کار به دلیل عدم رعایت HSE","probability":"متوسط","impact":"متوسط","level":"متوسط","current_action":"بازرسی هفتگی HSE و اخطار کتبی به پیمانکار"}]'::jsonb,
        'در صورت ادامه نرخ ردی فعلی، حدود دو کیلومتر از جوش‌های جبهه ۲ باید اسقاط و مجدداً اجرا شود که هم به زمان‌بندی و هم به کیفیت نهایی خط لطمه می‌زند',
        'نرخ بالای ردی جوش در جبهه ۲',
        'ضعف مهارت فنی بخشی از جوشکاران جدیدالورود پیمانکار و عدم اجرای کامل WPS مصوب',
        'توقف موقت جبهه، بازآموزی فشرده جوشکاران، و ارزیابی مجدد صلاحیت قبل از ازسرگیری',
        'تایید توقف موقت جبهه ۲ برای بازآموزی، با وجود اثر کوتاه‌مدت بر پیشرفت فیزیکی',
        'مهم – کمتر از ۱۴ روز', 'الزام آزمون صلاحیت جوشکاران قبل از ورود به سایت، نه بعد از شروع کار',
        'تشدید ردی جوش و اسقاط بخش قابل‌توجهی از جوش‌های انجام‌شده', 4,
        'Quality', null, '["افت کیفیت","تأخیر زمانی","افزایش هزینه"]'::jsonb, null,
        'ادامه این روند منجر به اسقاط و اجرای مجدد بخش قابل‌توجهی از جوش‌ها، افزایش هزینه مصالح و نیروی انسانی، و تاخیر در تکمیل جبهه ۲ خواهد شد',
        'بازآموزی فشرده و ارزیابی مجدد صلاحیت جوشکاران جبهه ۲ طی ۳۰ روز',
        'توقف موقت پذیرش جوش جدید در جبهه ۲، برگزاری دوره بازآموزی پنج‌روزه توسط مدرس واجد صلاحیت، و آزمون صلاحیت مجدد پیش از بازگشت به کار',
        'این اقدام مستقیماً ریشه مشکل را هدف می‌گیرد و از تشدید ردی و هزینه‌های اسقاط بیشتر جلوگیری می‌کند؛ ظرف کمتر از یک ماه قابل اجراست',
        'کاهش نرخ ردی جوش از شش درصد به زیر سه درصد ظرف ۳۰ روز',
        'بازآموزی و ارزیابی مجدد صلاحیت جوشکاران', 'مدیر QC مشاور', 'واحد کنترل کیفیت مشاور، واحد HSE پیمانکار، تامین‌کننده آموزش جوش', '2026-08-28', '2026-09-27',
        'تامین مدرس و محل برگزاری آموزش توسط پیمانکار', 'تایید مدیریت طرح برای توقف موقت جبهه ۲', 'گواهی صلاحیت مجدد جوشکاران و گزارش کاهش نرخ ردی',
        'نرخ ردی جوش (درصد)', 'شش درصد', 'کمتر از سه درصد',
        10, 3, 25000000000, 1, 2, 'جبهه جوشکاری شماره ۲', 'کاهش ریسک عدم تایید نهایی کیفیت توسط کارفرما',
        '["تصمیم مدیریت طرح","تأمین منابع مالی"]'::jsonb, null, 'تایید مدیریت طرح برای توقف موقت جبهه و تامین بودجه دوره بازآموزی', '۱۵ تا ۳۰ روز',
        'با رفع این مشکل، اعتماد کارفرما به کیفیت اجرای خط بازمی‌گردد و از اسقاط پرهزینه در ماه‌های آینده جلوگیری می‌شود'
    );

    -- 4. Contractor (پیمانکار) check-in
    insert into check_ins (
        created_at, user_id, project_name, organization,
        respondent, respondent_position, respondent_contact, qw_form_date,
        area_status, work_fronts,
        planned_progress, physical_progress, financial_progress, forecast_completion_date,
        manpower_count, weld_reject_rate, hse_incident, hse_incident_note,
        issues, risks,
        q_negative_event, main_bottleneck, bottleneck_root_cause, bottleneck_unlock_action,
        senior_decision_needed, senior_decision_priority, one_thing_to_change,
        top_risk, risk_severity,
        qw_bottleneck_area, qw_bottleneck_area_other, qw_consequences, qw_consequence_other, qw_consequence_description,
        quick_win_title, action_details, qw_rationale, tangible_result,
        plan_main_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date,
        plan_prerequisite, plan_decision_needed, plan_deliverable,
        kpi_name, kpi_current, kpi_target_30d,
        impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed, impact_docs_resolved, impact_fronts_freed, impact_other,
        support_types, support_other_text, support_needed, time_estimate, final_reflection
    ) values (
        v_ts_contractor, v_user_id, v_project, 'پیمانکار',
        'مهندس حسین کریمی', 'مدیر پروژه پیمانکار', 'h.karimi@pipelineco.ir', '2026-08-27',
        '{"engineering":{"status":"🟢 سبز","issue":"بدون مسئله باز"},"procurement":{"status":"🔴 قرمز","issue":"شیرآلات وارداتی در گمرک - بیش از سه هفته در انتظار ترخیص"},"construction":{"status":"🟡 زرد","issue":"کاهش سرعت جبهه ۲ به دلیل الزامات کیفی جدید"},"contract":{"status":"🟡 زرد","issue":"معطلی تایید صورت‌وضعیت دوره ۱۴"},"finance":{"status":"🔴 قرمز","issue":"کمبود نقدینگی به دلیل تاخیر بیش از ۴۵ روزه پرداخت"},"hse":{"status":"🟢 سبز","issue":"صفر حادثه ثبت‌شده در این دوره"},"quality":{"status":"🟡 زرد","issue":"در حال اجرای اقدامات اصلاحی نرخ ردی جوش"}}'::jsonb,
        '{"row":{"status":"🟢 سبز","issue":"بدون مسئله"},"pipe_supply":{"status":"🟢 سبز","issue":"موجودی کافی در انبار سایت"},"valve_equipment":{"status":"🔴 قرمز","issue":"شیرآلات ۳۰ اینچ در گمرک بندرعباس معطل"},"welding":{"status":"🟡 زرد","issue":"کاهش موقت سرعت به دلیل بازآموزی"},"ndt":{"status":"🟡 زرد","issue":"افزایش صف تست به دلیل تست‌های مجدد"},"coating":{"status":"🟢 سبز","issue":"مطابق برنامه"},"lowering":{"status":"🟢 سبز","issue":"بدون معطلی قابل‌توجه"},"backfilling":{"status":"🟢 سبز","issue":"جلوتر از برنامه در جبهه ۱"},"crossings":{"status":"🔴 قرمز","issue":"توقف کامل عبور رودخانه - منتظر مجوز"},"station_facility":{"status":"🟡 زرد","issue":"تجهیزات ایستگاه در حمل و نقل"}}'::jsonb,
        62, 59, 42, '2027-02-15',
        410, 5.5, false, null,
        '[{"description":"تاخیر بیش از ۴۵ روزه در تایید و پرداخت صورت‌وضعیت","impact":["هزینه","قرارداد"],"severity":"بالا"},{"description":"توقف گمرکی شیرآلات وارداتی","impact":["زمان","پیشرفت"],"severity":"بالا"},{"description":"کاهش سرعت جبهه ۲ به دلیل الزامات کیفی جدید مشاور","impact":["زمان","پیشرفت"],"severity":"متوسط"}]'::jsonb,
        '[{"risk":"توقف کامل عملیات به دلیل کمبود شدید نقدینگی","probability":"زیاد","impact":"زیاد","level":"بحرانی","current_action":"مکاتبه رسمی درخواست تسریع پرداخت"},{"risk":"افزایش هزینه دموراژ گمرکی شیرآلات","probability":"متوسط","impact":"متوسط","level":"متوسط","current_action":"پیگیری روزانه با نماینده گمرکی"},{"risk":"کاهش انگیزه نیروی انسانی به دلیل تاخیر حقوق","probability":"متوسط","impact":"زیاد","level":"زیاد","current_action":"تامین موقت از منابع داخلی شرکت"}]'::jsonb,
        'در صورت عدم پرداخت صورت‌وضعیت طی این ماه، احتمال کاهش نیروی انسانی سایت به دلیل ناتوانی در پرداخت حقوق وجود دارد که می‌تواند اجرای فیزیکی را متوقف کند',
        'معوقات مالی صورت‌وضعیت‌ها',
        'طولانی بودن فرآیند تایید فنی صورت‌وضعیت توسط مشاور و کارفرما',
        'تعیین سقف زمانی مشخص حداکثر چهارده روز برای چرخه تایید صورت‌وضعیت',
        'تصویب پرداخت علی‌الحساب بخشی از صورت‌وضعیت معوق تا تکمیل بررسی کامل',
        'فوری – کمتر از ۷ روز', 'کوتاه کردن چرخه تایید و پرداخت صورت‌وضعیت‌ها',
        'توقف عملیات به دلیل کمبود نقدینگی ناشی از تاخیر پرداخت', 5,
        'Finance', null, '["ایجاد Claim","توقف جبهه کاری","تأخیر زمانی"]'::jsonb, null,
        'ادامه تاخیر پرداخت می‌تواند به ادعای خسارت رسمی از سوی پیمانکار و کاهش تدریجی نیروی انسانی سایت منجر شود',
        'پرداخت علی‌الحساب هفتاد درصد صورت‌وضعیت دوره ۱۴ ظرف ۱۰ روز',
        'بررسی فوری و پرداخت علی‌الحساب بخش غیرمناقشه‌برانگیز صورت‌وضعیت (هفتاد درصد مبلغ) بدون انتظار برای تکمیل بررسی صد درصد اقلام',
        'این اقدام کم‌هزینه‌ترین و سریع‌ترین راه برای رفع فوری‌ترین ریسک پروژه یعنی توقف احتمالی عملیات است',
        'تزریق نقدینگی و تضمین تداوم کار تا تکمیل بررسی کامل صورت‌وضعیت',
        'پرداخت علی‌الحساب بخش تاییدشده صورت‌وضعیت', 'مدیر مالی کارفرما (با هماهنگی پیمانکار)', 'امور مالی کارفرما، دفتر فنی مشاور، پیمانکار', '2026-08-27', '2026-09-06',
        'تایید فنی حداقلی هفتاد درصد اقلام صورت‌وضعیت توسط مشاور', 'تصویب پرداخت علی‌الحساب توسط مدیریت مالی کارفرما', 'فیش پرداخت علی‌الحساب صورت‌وضعیت دوره ۱۴',
        'روزهای معوق پرداخت صورت‌وضعیت', '۴۵ روز', 'کمتر از ۱۰ روز',
        20, 5, 15000000000, 1, 1, 'کلیه جبهه‌های فعال (رفع ریسک کاهش نیرو)', 'جلوگیری از ثبت ادعای خسارت رسمی',
        '["تصمیم مدیریت طرح","تأمین منابع مالی"]'::jsonb, null, 'تصویب و ابلاغ فوری پرداخت علی‌الحساب توسط مدیریت مالی کارفرما', 'کمتر از ۷ روز',
        'پرداخت به‌موقع مهم‌ترین عامل حفظ روحیه و تداوم کار نیروی انسانی در این مقطع حساس پروژه است'
    );

    -- 5. Form 1 (client_reports) — basic contract info + progress/schedule + milestone
    insert into client_reports (
        user_id, project_name, plan_name, contract_number, contract_type, contract_type_other,
        contractor_name, consultant_name, client_pm_name, contractor_pm_name, consultant_pm_name,
        contract_initial_amount_rial, contract_initial_amount_eur, contract_current_amount_rial, contract_current_amount_eur,
        contract_start_date, contract_end_date,
        contract_duration_months, elapsed_months,
        progress_planned, progress_physical, progress_engineering, progress_procurement, progress_construction,
        milestone_name, milestone_planned_date, milestone_status, milestone_delay_days
    ) values (
        v_user_id, v_project, 'طرح خط انتقال گاز ششم سراسری', 'GC-6TH-1404-018', 'EPC', null,
        'شرکت پیمانکاری خطوط انتقال پارس', 'مهندسین مشاور طراحان انرژی', 'مهندس علی رضایی', 'مهندس حسین کریمی', 'دکتر سارا احمدی',
        4200, 85, 4650, 92, '2024-09-22', '2027-03-21',
        30, 23,
        62, 54, 92, 68, 51,
        'تکمیل عبور از رودخانه قزل‌اوزن و اتصال جبهه‌های ۱ و ۲', '2026-10-15', 'در معرض تأخیر', 25
    );

    -- 6. Admin evaluation of all three proposals (quick_win_evaluations)
    insert into quick_win_evaluations (project_name, organization, proposal_created_at, score_time, score_cost, score_urgency, score_feasibility, score_leverage, weighted_score, decision, evaluated_by)
    values
        (v_project, 'کارفرما', v_ts_client, 5, 4, 5, 5, 5, 4.80, 'Quick Win منتخب', v_email),
        (v_project, 'مشاور', v_ts_consultant, 3, 4, 3, 4, 3, 3.40, 'نیازمند بررسی بیشتر', v_email),
        (v_project, 'پیمانکار', v_ts_contractor, 4, 3, 5, 5, 4, 4.20, 'ادغام با پیشنهاد دیگر', v_email);

    -- 7. Selected Quick Win (کارفرما's permit-expediting proposal won — highest cross-front leverage)
    insert into quick_win_decisions (
        project_name, selected_organization, selected_title, selected_action, selected_result, selected_support,
        impact_score, feasibility_score, cost_score, priority_score, rationale, decided_by, target_date
    ) values (
        v_project, 'کارفرما', 'اخذ مجوز موقت عبور از رودخانه قزل‌اوزن طی ۳۰ روز',
        'برگزاری جلسه فوری با مدیرکل محیط‌زیست استان، تکمیل و ارسال مدارک تکمیلی درخواستی ظرف پنج روز کاری، و پیگیری روزانه تا صدور مجوز موقت اجرا',
        'صدور مجوز موقت و از سرگیری عملیات عبور از رودخانه ظرف ۳۰ روز',
        'مکاتبه رسمی مدیرعامل با استانداری و پیگیری حقوقی موازی',
        5, 5, 4, 4.80, 'بالاترین اثر زنجیره‌ای بر کل جبهه‌های اجرایی طرح و کمترین زمان تحقق در بین پیشنهادهای سه‌گانه', v_email, '2026-09-24'
    );

    -- 8. Progress log for the selected Quick Win
    insert into quick_win_progress (created_at, project_name, status, progress_percent, note, reported_by) values
        ('2026-08-28 08:00:00+00', v_project, 'در حال انجام', 20, 'جلسه اول با اداره محیط‌زیست برگزار و فهرست مدارک تکمیلی دریافت شد', v_email),
        ('2026-09-04 08:00:00+00', v_project, 'در حال انجام', 50, 'مدارک تکمیلی ارسال و در انتظار بررسی کارشناسی است', v_email),
        ('2026-09-12 08:00:00+00', v_project, 'با مانع مواجه', 55, 'بررسی کارشناسی به دلیل تعطیلات اداری یک هفته به تعویق افتاد', v_email),
        ('2026-09-18 08:00:00+00', v_project, 'در حال انجام', 75, 'بازدید میدانی کارشناس محیط‌زیست انجام و نظر فنی مثبت اعلام شد', v_email);

end $$;

-- ============================================================
-- Cleanup (commented out) — run this later if you want to remove
-- only this demo project and nothing else:
--
-- delete from quick_win_progress where project_name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- delete from quick_win_decisions where project_name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- delete from quick_win_evaluations where project_name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- delete from client_reports where project_name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- delete from check_ins where project_name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- delete from projects where name = 'خط ۳۰ اینچ چالوند–اردبیل (نمونه آزمایشی)';
-- ============================================================
