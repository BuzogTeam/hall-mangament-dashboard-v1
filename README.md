# University Hall Management System

لوحة إدارة عربية RTL لإدارة مباني الجامعة وقاعاتها وأقسامها ودفعاتها وموادها ومدرسيها ومحاضراتها. التطبيق React + Vite + JavaScript + Tailwind + React Router + Supabase، وجميع البيانات التشغيلية تأتي من Supabase بدون Mock Data. يستخدم المشروع خط Cairo Variable محليًا من حزمة مفتوحة المصدر، لذلك لا يعتمد على Google Fonts أو أي طلب خارجي للخط.

## التشغيل

```bash
npm install
npm run dev
```

انسخ `.env.example` إلى `.env` وأضف بيانات Supabase. تم إعداد `.env` الحالي بالقيم التي تم تزويدها للمشروع.

## تهيئة Supabase

1. راجع `supabase/inspection.md` و`supabase/inspection.sql`. تم فحص الجداول والقيم المرصودة قبل بناء النماذج.
2. شغّل `supabase/schema.sql` لإضافة `profiles`, `roles`, `permissions`, `role_permissions` فقط. الملف لا يمنح العملاء صلاحيات كتابة مباشرة على جداول التفويض، ويستخدم `roles.key` كمصدر وحيد للدور، ويفعّل RLS الجديدة في وضع fail-closed.
3. شغّل `supabase/functions.sql` لإضافة helper functions وRPCs الآمنة للملف الشخصي وإدارة المستخدمين والصلاحيات وفحص تعارضات المحاضرات. الكتابة على profiles وrole_permissions تتم عبر RPC فقط.
   إذا كانت ملفات SQL السابقة منفذة بالفعل، شغّل migration الإضافية `supabase/migrations/20260825_add_lecture_lifecycle_rpc.sql` لأن الواجهة تستخدم `set_lecture_canceled()` لإلغاء/إعادة تفعيل المحاضرات بأمان. ولإصلاح CRUD جدول الأقسام في تثبيتات RLS الحالية، شغّل `supabase/migrations/20260825_fix_departments_crud.sql`. ولإصلاح CRUD المستويات عند ظهور خطأ RLS، شغّل `supabase/migrations/20260825_fix_levels_crud.sql`. وبما أن نقص Policies ظهر في أكثر من جدول أكاديمي، فالخيار الموصى به هو تشغيل Migration الشاملة `supabase/migrations/20260826_fix_authenticated_academic_crud.sql`؛ فهي تعالج CRUD للمباني والقاعات والأقسام والمستويات والدفعات والمواد والمدرسين والمحاضرات دون منح `anon` صلاحيات أو تغيير حالة RLS. توجد أيضًا Migrations مستهدفة لكل جدول عند الحاجة. وإذا ظهر خطأ `new.updated_at` عند تعديل قسم أو مستوى أو مدرس، شغّل `supabase/migrations/20260825_fix_invalid_updated_at_triggers.sql`.
4. شغّل `supabase/policies.sql` لتثبيت RLS الخاصة بالجداول الجديدة. هذا الملف لا يغيّر RLS للجداول الأكاديمية الحالية.
5. أنشئ أول مستخدم من Supabase Auth، ثم امنحه يدويًا دور `super_admin` في جدول `profiles`:

```sql
update public.profiles
set role = 'super_admin', is_active = true
where email = 'admin@example.com';
```

6. `supabase/academic-policies.sql` اختيارية. لا تشغّلها قبل التأكد من أن تطبيق Flutter يستخدم Supabase Auth؛ فهي تفعّل RLS على الجداول الأكاديمية الحالية وقد تمنع وصول العميل المجهول.
7. لإتاحة دعوة مستخدمين من صفحة المستخدمين، انشر `supabase/functions/create-user/index.js` واضبط Secrets كما هو موضح في README داخل مجلد الدالة.

لتفعيل نطاقات مديري الأقسام وحجوزات القاعات في التثبيت الحالي، وبعد تطبيق `schedule_hardening.sql` مسبقًا، نفّذ Migration الجديدة مرة واحدة من SQL Editor:

```text
supabase/migrations/20260827_phase1_scope_occurrence_reservations.sql
```

تضيف هذه Migration:

- إعادة استخدام `department_levels` و`department_manager_scopes` و`hall_reservations` الموجودة؛ لا تنشئ هذه Migration جداول مكررة لها.
- `lecture_occurrence_overrides` للإلغاء المؤقت في تاريخ واحد.
- `lecture_occurrence_history` لتسجيل تغييرات occurrence.
- دعم الحجوزات الأسبوعية عبر `day_of_week` أو المؤقتة عبر `reservation_date` دون تحويل التاريخ إلى يوم أسبوع.
- منع القاعة ذات `booking = true` من الجدولة.
- منع تعارضات القاعات في RPC وDatabase Triggers مع قفل موحّد.
- RPC إدارة النطاقات والحجوزات والإلغاء المؤقت.
- Scope-aware RLS للدفعات والمحاضرات، مع Fail-Closed عند غياب Scope.

الحجز المؤقت لا يلغي المحاضرة تلقائيًا؛ يجب إلغاء occurrence أولًا إذا كانت القاعة مشغولة بمحاضرة في ذلك التاريخ.

لتفعيل إدارة مدير القسم للحجوزات المؤقتة داخل Scope فقط، وبعد تشغيل Migration المرحلة الأولى السابقة، شغّل Migration الإضافة:

```text
supabase/migrations/20260830_department_manager_temporary_reservation_scope.sql
```

تضيف هذه Migration أعمدة Scope اختيارية إلى `hall_reservations` للحفاظ على التوافق مع الحجوزات العامة القديمة، وتمنح Department Manager مفاتيح الحجوزات الموجودة أصلًا، مع قصره على الحجز المؤقت فقط.

إذا تم تغيير `lectures.group` إلى `lectures.groups` كمصفوفة، شغّل بعد ذلك Migration إصلاح المجموعات:

```text
supabase/migrations/20260830_lecture_groups_array_conflict_repair.sql
```

هذه Migration تعيد Trigger حماية الجدول، وتستخدم تقاطع المصفوفات لمنع التعارض بين نفس المجموعة فقط، مع إبقاء تعارض القاعة والمدرس عامًا.

لا تحذف هذه Migrations صفوف الجداول الأكاديمية أو تعيد تنفيذ Migrations الجدول السابقة. التغيير المقصود على بيانات التفويض هو منح Department Manager صلاحيات الحجوزات المؤقتة ضمن Scope.

إذا كانت Migration النطاقات والحجوزات قد توقفت عند تعليق `SCHEDULE RPC/trigger overrides`، فلا تعِد تشغيل الملف القديم أو Migration الإصلاح القديمة؛ استخدم Migration المرحلة الأولى الحالية أعلاه.

## الوظائف المنفذة

- تسجيل الدخول عبر Supabase Auth، استعادة الجلسة، وحظر الحساب غير النشط.
- Profile وRBAC وأدوار: مدير النظام الأعلى، مدير، مسؤول الجداول، مدير قسم، مشاهد.
- Layout متجاوب RTL مع Drawer للهاتف وLight/Dark/System.
- Dashboard بإحصائيات حقيقية، جدول اليوم، حالة القاعات، الرسوم، والنشاط الأخير.
- CRUD للمباني والقاعات والأقسام والمستويات والدفعات والمواد والمدرسين.
- إدارة المحاضرات مع بحث وفلاتر وإلغاء بدل الحذف وفحص تعارض القاعة والمدرس والدفعة.
- جدول يومي وأسبوعي وعروض حسب القاعة أو المدرس أو الدفعة.
- المستخدمون، الصلاحيات، التقارير والإعدادات.
- Loading / Error / Empty states وConfirm Dialog وToast notifications.

## ملاحظات البيانات الحالية

القيم الحالية للـ ENUM محفوظة في `inspection.md`. التطبيق يقرأ القيم المستخدمة من الجداول عبر `metadataService`، ولا يزرع بيانات تجريبية. إذا كانت القاعدة فارغة ستظهر الحالات الفارغة بدل أرقام مصطنعة.

## النشر ومشاركة الرابط

### Preview مؤقت

يمكن مشاركة رابط Live Preview الظاهر في لوحة Arena، لكنه مؤقت وقد يتوقف عند انتهاء جلسة الخادم.

### Vercel

- ارفع المستودع إلى GitHub بدون `.env`.
- استورد المستودع في Vercel.
- Build Command: `npm run build`.
- Output Directory: `dist`.
- أضف متغيري `VITE_SUPABASE_URL` و`VITE_SUPABASE_PUBLISHABLE_KEY` في Vercel.
- ملف `vercel.json` موجود لمعالجة React Router.
- أضف رابط Vercel إلى Supabase Authentication URL Configuration.

### Netlify

ملف `netlify.toml` موجود ويحدد build command وSPA redirect. أضف نفس متغيرات البيئة في إعدادات Netlify.

لا تشارك كلمة مرور Super Admin. أنشئ حساب Viewer أو حساب اختبار لصديقك من Supabase Auth، ويمكنه فتح الرابط وتسجيل الدخول بحسابه.
