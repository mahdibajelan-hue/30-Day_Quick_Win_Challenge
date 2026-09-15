-- ============================================================
-- Master data seed for the Project Lifecycle & Stage-Gate module —
-- NOT a migration; run once, manually, in the Supabase SQL Editor,
-- AFTER 033_lifecycle_stage_gate.sql has been applied. Safe to re-run:
-- it clears the 6 lifecycle master tables first, then reinserts a fresh
-- copy (per-project data in project_lifecycle_phases/project_phase_items
-- is untouched).
--
-- SOURCE: «مدل چرخه عمر پروژه‌های شرکت مهندسی و توسعه گاز ایران»
-- (Rev.01, 1405-06-17) — the organization's official lifecycle
-- infographic, extracted via vision/OCR as instructed. Two things to
-- know about this extraction before treating it as final:
--
-- 1. RECONCILING 10 IMAGE COLUMNS INTO 9 OFFICIAL GATES. The reference
--    image lays out 10 phase columns separated by 9 gate diamonds:
--    تعریف پروژه / شفاف‌سازی پروژه / برنامه‌ریزی کلان پروژه / خرید خدمات
--    مشاور طراحی پایه / طراحی پایه / مناقصه انتخاب پیمانکار و ناظر /
--    اجرا / پیش‌راه‌اندازی و راه‌اندازی / دوره نگهداری / تسویه حساب.
--    The module's authoritative structure (per the written brief this
--    was built from, which is explicit that G4 = Basic Design only,
--    G5 = tender/contract, G6 = the one and only EPC/execution phase,
--    and there are exactly 9 gates) merges the image's «شفاف‌سازی
--    پروژه» and «برنامه‌ریزی کلان پروژه» columns into a single G2 —
--    «شناسایی پروژه» — without dropping any bullet: everything under
--    both image columns is kept, split across G2's Objectives/Outputs/
--    Criteria below. Every other phase maps one-to-one onto the image.
-- 2. OCR CONFIDENCE. Phase titles, the responsible column, gate names
--    and the % thresholds are large, clearly-legible text in the
--    source image and are transcribed with high confidence. The dense
--    small-print bullets under «اهداف مرحله» / «خروجی کلیدی» / «معیار
--    عبور» are a best-effort reading; a handful of individual bullets
--    carry a trailing "[NEEDS REVIEW]" where a word or phrase could not
--    be read with confidence, per the instruction to flag rather than
--    invent. PMO should verify every [NEEDS REVIEW] item against the
--    original document before relying on it operationally — this seed
--    is a starting point for the editable master data, not a final
--    signed-off record.
-- ============================================================

delete from lifecycle_criteria;
delete from lifecycle_outputs;
delete from lifecycle_objectives;
delete from lifecycle_phases;

-- ---- 1. Phases (master template) ----
insert into lifecycle_phases (code, sort_order, phase_group, title, responsible, gate_name, gate_threshold_pct, progress_engine, icon_key, objectives_weight_pct, outputs_weight_pct, criteria_weight_pct) values
('G1', 1, 'fel',           'تعریف پروژه',                                  'شرکت ملی گاز',                                   'تصویب و ابلاغ',                                             30,  'step',         'target',      50, 30, 20),
('G2', 2, 'fel',           'شناسایی پروژه',                                 'شرکت ملی گاز / برنامه‌ریزی و کنترل طرح‌ها',        'صدور مجوز خرید خدمات',                                       50,  'step',         'users',       50, 30, 20),
('G3', 3, 'execution',     'خرید خدمات مشاور',                              'مجری طرح',                                       'ابلاغ شروع به کار مهندسی',                                    70,  'step',         'clipboard',   50, 30, 20),
('G4', 4, 'execution',     'طراحی پایه',                                    'مجری طرح',                                       'مجوز کمیسیون/هیات فنی برای برگزاری مناقصات',                  80,  'basic_design', 'fileText',    50, 30, 20),
('G5', 5, 'execution',     'مناقصه انتخاب پیمانکار و انعقاد قرارداد',        'مجری طرح',                                       'ابلاغ شروع به کار اجرا',                                      90,  'step',         'tool',        50, 30, 20),
('G6', 6, 'execution',     'اجرای پروژه',                                   'مجری طرح',                                       'تایید شروع پیش‌راه‌اندازی',                                    100, 'epc',          'zap',         50, 30, 20),
('G7', 7, 'commissioning', 'پیش‌راه‌اندازی و راه‌اندازی',                     'مجری طرح',                                       'تحویل موقت توسط بهره‌بردار',                                   100, 'step',         'gauge',       50, 30, 20),
('G8', 8, 'commissioning', 'دوره نگهداری',                                  'مجری طرح',                                       'تحویل قطعی',                                                 100, 'step',         'shield',      50, 30, 20),
('G9', 9, 'commissioning', 'تسویه حساب',                                    'مجری طرح',                                       'تایید نهایی و بستن پروژه [NEEDS REVIEW]',                     100, 'step',         'checkCircle', 50, 30, 20);

-- ---- 2. G1 — تعریف پروژه ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G1', 1, 'طرح ایده پروژه'),
('G1', 2, 'امکان‌سنجی'),
('G1', 3, 'تهیه گزارش توجیهی'),
('G1', 4, 'ابلاغ و ثبت پروژه [NEEDS REVIEW]');
insert into lifecycle_outputs (phase_code, seq, title) values
('G1', 1, 'گزارش امکان‌سنجی و توجیه فنی-اقتصادی'),
('G1', 2, 'گزارش توجیهی پروژه');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G1', 1, 'تصویب پروژه توسط مراجع ذی‌ربط', true),
('G1', 2, 'ابلاغ پروژه', true);

-- ---- 3. G2 — شناسایی پروژه (شفاف‌سازی پروژه + برنامه‌ریزی کلان پروژه) ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G2', 1, 'بررسی مصوبه هیات مدیره'),
('G2', 2, 'بررسی گزارش امکان‌سنجی و توجیهی'),
('G2', 3, 'تعیین مجری طرح'),
('G2', 4, 'استخراج ابهامات پروژه'),
('G2', 5, 'رفع ابهامات پروژه'),
('G2', 6, 'تعیین روش اجرای پروژه'),
('G2', 7, 'تهیه زمان‌بندی و برآورد کل پروژه'),
('G2', 8, 'تعیین بودجه و اخذ مجوز آن'),
('G2', 9, 'تهیه شرح کار و اسناد خرید خدمات مشاور'),
('G2', 10, 'برآورد کمیت تسهیلات موردنیاز'),
('G2', 11, 'تحصیل اراضی، در صورت نیاز [NEEDS REVIEW]');
insert into lifecycle_outputs (phase_code, seq, title) values
('G2', 1, 'منشور پروژه'),
('G2', 2, 'گزارش شفاف‌سازی و رفع ابهامات'),
('G2', 3, 'برنامه مدیریت پروژه (PMP)'),
('G2', 4, 'خط مبنای زمان و هزینه اولیه'),
('G2', 5, 'شرح خدمات و اسناد خرید خدمات مشاور');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G2', 1, 'تصویب منشور پروژه و ابلاغ آغاز مقدمات پروژه', true),
('G2', 2, 'صدور مجوز خرید خدمات مشاور', true);

-- ---- 4. G3 — خرید خدمات مشاور ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G3', 1, 'تهیه اسناد ارزیابی کیفی مشاوران'),
('G3', 2, 'ارزیابی کیفی مشاوران توسط کمیته فنی و بازرگانی'),
('G3', 3, 'تهیه فهرست کوتاه مشاوران'),
('G3', 4, 'بازنگری اسناد مناقصه، در صورت نیاز'),
('G3', 5, 'ارزیابی مالی و تعیین برنده توسط هیات انتخاب مشاور'),
('G3', 6, 'تصویب انتخاب مشاور توسط هیات مدیره'),
('G3', 7, 'ابلاغ شروع به کار به مشاور');
insert into lifecycle_outputs (phase_code, seq, title) values
('G3', 1, 'گزارش ارزیابی کیفی پیشنهادها'),
('G3', 2, 'فهرست کوتاه مشاوران'),
('G3', 3, 'مصوبه انتخاب مشاور'),
('G3', 4, 'قرارداد خدمات مشاور طراحی پایه');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G3', 1, 'تایید هیات مدیره برای انتخاب مشاور', true),
('G3', 2, 'ابلاغ شروع به کار مهندسی', true);

-- ---- 5. G4 — طراحی پایه ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G4', 1, 'تهیه نقشه‌ها و مدارک مهندسی پایه'),
('G4', 2, 'تهیه مشخصات فنی پایه'),
('G4', 3, 'بررسی و بازنگری نقشه‌ها و مدارک توسط مشاور'),
('G4', 4, 'تایید مدارک طراحی پایه توسط مجری طرح');
insert into lifecycle_outputs (phase_code, seq, title) values
('G4', 1, 'بسته مصوب طراحی پایه'),
('G4', 2, 'نقشه‌ها و مشخصات فنی پایه'),
('G4', 3, 'برآورد به‌روزشده هزینه و زمان‌بندی پروژه');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G4', 1, 'تایید اسناد و مدارک طراحی پایه', true),
('G4', 2, 'صدور مجوز کمیسیون/هیات فنی برای برگزاری مناقصات', true);

-- ---- 6. G5 — مناقصه انتخاب پیمانکار و انعقاد قرارداد ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G5', 1, 'تکمیل اسناد ارزیابی کیفی پیمانکاران و ناظر'),
('G5', 2, 'ارزیابی کیفی پیمانکاران و ناظر توسط کمیته فنی و بازرگانی'),
('G5', 3, 'تهیه فهرست کوتاه پیمانکاران و ناظر'),
('G5', 4, 'برگزاری مناقصه طبق شرح کار'),
('G5', 5, 'ارزیابی مالی و تعیین برنده'),
('G5', 6, 'اخذ مجوز و انعقاد قرارداد');
insert into lifecycle_outputs (phase_code, seq, title) values
('G5', 1, 'فهرست کوتاه پیمانکاران و ناظر'),
('G5', 2, 'گزارش ارزیابی مناقصه'),
('G5', 3, 'قرارداد پیمانکار اجرا'),
('G5', 4, 'قرارداد ناظر');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G5', 1, 'تصویب هیات انتخاب پیمانکار', true),
('G5', 2, 'ابلاغ شروع به کار اجرا', true);

-- ---- 7. G6 — اجرای پروژه (EPC) ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G6', 1, 'تحویل زمین به پیمانکار'),
('G6', 2, 'تهیه و تصویب پکیج‌های اجرایی'),
('G6', 3, 'تدوین برنامه نظارت پروژه و روش هماهنگی'),
('G6', 4, 'اجرای شرح کار مطابق پیمان'),
('G6', 5, 'اعلام آمادگی پیمانکار جهت تکمیل و پیش‌راه‌اندازی');
insert into lifecycle_outputs (phase_code, seq, title) values
('G6', 1, 'مدارک اجرایی تفصیلی'),
('G6', 2, 'صورت‌وضعیت‌های دوره‌ای پیشرفت'),
('G6', 3, 'گزارش دوره‌ای پیشرفت مهندسی/تدارکات/اجرا (E/P/C)');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G6', 1, 'تکمیل فیزیکی اجرا مطابق برنامه', true),
('G6', 2, 'تایید شروع پیش‌راه‌اندازی', true);

-- ---- 8. G7 — پیش‌راه‌اندازی و راه‌اندازی ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G7', 1, 'انجام PSSR (بازرسی ایمنی پیش از راه‌اندازی)'),
('G7', 2, 'انجام تست‌های پیش‌راه‌اندازی و رفع موانع'),
('G7', 3, 'اعلام آمادگی پیمانکار جهت راه‌اندازی'),
('G7', 4, 'اخذ مجوز راه‌اندازی'),
('G7', 5, 'تهیه فهرست نواقص (Punch List) توسط بهره‌بردار'),
('G7', 6, 'تکمیل و ارسال فرم تحویل موقت');
insert into lifecycle_outputs (phase_code, seq, title) values
('G7', 1, 'گزارش PSSR'),
('G7', 2, 'گواهی تکمیل مکانیکی'),
('G7', 3, 'صورتجلسه تحویل موقت');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G7', 1, 'تایید راه‌اندازی توسط بهره‌بردار', true),
('G7', 2, 'امضای صورتجلسه تحویل موقت', true);

-- ---- 9. G8 — دوره نگهداری ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G8', 1, 'رفع نواقص باقیمانده فهرست تحویل موقت'),
('G8', 2, 'تحویل کلیه مدارک و مستندات پروژه (فایل نهایی/Vital Book) [NEEDS REVIEW]'),
('G8', 3, 'تکمیل تاسیسات جانبی، در صورت نیاز [NEEDS REVIEW]'),
('G8', 4, 'اعلام آمادگی جهت تحویل قطعی');
insert into lifecycle_outputs (phase_code, seq, title) values
('G8', 1, 'مستندات نهایی پروژه (As-Built)'),
('G8', 2, 'گواهی پایان دوره نگهداری');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G8', 1, 'رفع کامل نواقص فهرست‌شده', true),
('G8', 2, 'امضای صورتجلسه تحویل قطعی', true);

-- ---- 10. G9 — تسویه حساب ----
insert into lifecycle_objectives (phase_code, seq, title) values
('G9', 1, 'تهیه صورت‌وضعیت قطعی'),
('G9', 2, 'تهیه صورت‌وضعیت تعدیل قطعی'),
('G9', 3, 'نهایی‌سازی لایحه تاخیرات'),
('G9', 4, 'تایید متریال بازگشتی'),
('G9', 5, 'اخذ مفاصا حساب (بیمه/مالیات)'),
('G9', 6, 'آزادسازی تضامین'),
('G9', 7, 'اخذ تعهدنامه عدم ادعا'),
('G9', 8, 'صدور گواهی پایان کار نظارت');
insert into lifecycle_outputs (phase_code, seq, title) values
('G9', 1, 'صورت‌وضعیت قطعی و تعدیل قطعی'),
('G9', 2, 'گواهی مفاصا حساب'),
('G9', 3, 'گزارش نهایی پروژه و درس‌آموخته‌ها');
insert into lifecycle_criteria (phase_code, seq, title, is_mandatory) values
('G9', 1, 'تسویه کامل حساب‌های مالی', true),
('G9', 2, 'تایید و امضای گزارش نهایی اتمام پروژه', true);
