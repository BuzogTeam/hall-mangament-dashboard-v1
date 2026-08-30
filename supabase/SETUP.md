# دليل تشغيل University Hall Management System

هذا الدليل يشرح تشغيل الواجهة وتجهيز Supabase دون حذف أو نقل أي بيانات من الجداول الأكاديمية الحالية.

> لم يتم تنفيذ أي SQL عن بعد أثناء بناء المشروع. يجب تنفيذ الملفات من Supabase SQL Editor يدويًا.

## 1. المتطلبات

- Node.js 18 أو أحدث.
- npm.
- حساب يملك صلاحية SQL Editor في مشروع Supabase.
- اختياري: Supabase CLI لنشر Edge Function.

تحقق من Node وnpm:

```bash
node --version
npm --version
```

## 2. تشغيل الواجهة محليًا

من جذر المشروع:

```bash
npm install
npm run dev
```

افتح الرابط الذي يظهر في الطرفية، غالبًا:

```text
http://localhost:5173
```

تم إعداد `.env` بقيم Supabase التي تم تزويدها للمشروع. عند نقل المشروع إلى جهاز آخر، انسخ `.env.example` إلى `.env` وضع:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

مفتاح `VITE_SUPABASE_PUBLISHABLE_KEY` هو مفتاح عميل، ولا تضع أبدًا `SUPABASE_SERVICE_ROLE_KEY` في `.env` الخاص بالواجهة.

للتأكد من أن نسخة الإنتاج تبنى بنجاح:

```bash
npm run build
npm run preview
```

## 3. فحص قاعدة البيانات قبل التهيئة

الملف التالي ليس Migration:

```text
supabase/inspection.sql
```

يمكن تشغيله اختياريًا من SQL Editor لعرض:

- أسماء وقيم ENUM.
- العلاقات وForeign Keys.
- Views وFunctions.
- حالة RLS والسياسات الحالية.

يوجد ملخص للفحص السابق في:

```text
supabase/inspection.md
```

## 4. تنفيذ ملفات SQL بالترتيب

افتح Supabase Dashboard ثم:

```text
Project → SQL Editor → New query
```

انسخ كل ملف في Query مستقل ونفذه بالترتيب التالي، وانتظر نجاح كل ملف قبل تنفيذ التالي:

### الخطوة الأولى: `schema.sql`

نفّذ:

```text
supabase/schema.sql
```

هذا الملف يقوم بـ:

- إنشاء `roles`.
- إنشاء `permissions`.
- إنشاء `profiles`.
- إنشاء `role_permissions`.
- ربط `profiles.role` بـ `roles.key` باستخدام Foreign Key.
- إدخال الأدوار والصلاحيات الأساسية.
- إنشاء Profile تلقائيًا عند إنشاء مستخدم Auth.
- إنشاء Profiles للمستخدمين الموجودين مسبقًا عبر Backfill.
- تفعيل RLS على الجداول الجديدة بوضع Fail-Closed.
- منح صلاحية القراءة فقط للعميل `authenticated`.

هذا الملف لا يستخدم:

```text
DROP TABLE
TRUNCATE
```

ولا يعدل أعمدة أو صفوف الجداول:

```text
buildings
halls
departments
levels
batches
subjects
instructors
lectures
```

يضيف فقط Indexes بسيطة على جداول النظام الجديدة، ويضيف Trigger خاصًا اسمه:

```text
profiles_on_auth_user_created
```

### الخطوة الثانية: `functions.sql`

نفّذ:

```text
supabase/functions.sql
```

هذا الملف يقوم بـ:

- إنشاء دوال فحص المستخدم النشط والدور والصلاحيات.
- إنشاء `update_my_profile()` لتعديل اسم المستخدم فقط.
- إنشاء `admin_update_profile()` لإدارة Profiles بواسطة Super Admin.
- إنشاء `set_role_permission()` لتعديل الصلاحيات بواسطة Super Admin.
- إنشاء `find_lecture_conflicts()` لفحص تعارضات القاعة والمدرس والدفعة.
- التحقق من صحة الوقت والمدخلات والقيم الموجودة في ENUM.
- إنشاء ثلاثة Partial Indexes لتعارضات المحاضرات.

الفهارس الجديدة لا تغير البيانات ولا تضيف أعمدة. وهي:

```text
lectures_conflict_hall_idx
lectures_conflict_instructor_idx
lectures_conflict_batch_idx
```

### بعد تطبيق الـMigrations الأساسية (التثبيت الحالي)

بما أن `schedule_hardening.sql` تم تطبيقه مسبقًا، لا تعِد تشغيله. لتفعيل نطاقات مديري الأقسام والحجوزات مع الإلغاء المؤقت، شغّل Migration المرحلة الأولى الجديدة:

```text
supabase/migrations/20260827_phase1_scope_occurrence_reservations.sql
```

تضيف هذه Migration:

- إعادة استخدام `department_levels`, `department_manager_scopes`, و`hall_reservations` الموجودة بدل إنشاء بدائل.
- `lecture_occurrence_overrides` لإلغاء محاضرة في تاريخ واحد فقط.
- `lecture_occurrence_history` لتسجيل إلغاء/إعادة occurrence.
- دعم الحجز الأسبوعي والحجز المؤقت بتاريخ محدد دون تحويل التاريخ إلى يوم أسبوع.
- RPC إنشاء/تعديل/إلغاء/تفعيل الحجز.
- RPC إلغاء/إعادة occurrence.
- منع `booking = true` من الجدولة.
- Scope-aware RLS لمديري الأقسام.
- فصل صلاحية `lectures.cancel_series` عن `lectures.cancel_occurrence`.
- Trigger قاعدة بيانات للحجوزات، مع قفل موحّد يمنع سباق الحجز/المحاضرة وتغيير `halls.booking`.

الـMigration لا تحذف أو تعدل صفوف الجداول الأكاديمية، ولا تحذف Policies أو Triggers غير التابعة لها. الإضافة الوحيدة المقصودة إلى بيانات الصلاحيات هي إضافة مفاتيح المرحلة، مع إزالة منح `lectures.cancel` القديم من دور Department Manager حتى لا يحتفظ بإلغاء السلسلة عالميًا. الحجوزات بتاريخ محدد تقارن مع occurrence لذلك التاريخ فقط، ويجب إلغاء occurrence يدويًا قبل إنشاء حجز يتعارض مع محاضرة؛ لا يوجد إلغاء تلقائي.

إذا كنت قد شغّلت نسخة جزئية من Migration السابقة التي أنشأت الجداول الأولى فقط، استخدم النسخة النهائية للمرحلة الأولى بدل إعادة تشغيل الملف القديم. راجع توافقها مع Flutter قبل التنفيذ، خصوصًا لأن سياسات authenticated للدفعات والمحاضرات أصبحت تعتمد على Scope عند وجوده.

بعد تطبيق Migration المرحلة الأولى، شغّل Migration الإضافة الخاصة بإدارة مدير القسم للحجوزات المؤقتة:

```text
supabase/migrations/20260830_department_manager_temporary_reservation_scope.sql
```

هذه الإضافة تستخدم مفاتيح `hall_reservations.*` الموجودة، وتضيف Scope اختياريًا للحجز، وتسمح لمدير القسم بالحجوزات المؤقتة فقط داخل Scope. لا تعِد تشغيل أي Migration قديمة.

لا تحتاج إلى تشغيل الـMigrations المستهدفة القديمة التالية إذا كانت مشاكلها عولجت سابقًا، لأن Migration الشاملة تحتوي سياسات الجداول:

```text
20260825_fix_departments_crud.sql
20260825_fix_levels_crud.sql
20260826_fix_batches_crud.sql
20260826_fix_subjects_crud.sql
20260826_fix_instructors_crud.sql
20260826_fix_authenticated_academic_crud.sql
```

أما Migration تنظيف Triggerات `updated_at` فهي مستقلة ويمكن تشغيلها إذا لم تكن شُغّلت سابقًا:

```text
20260825_fix_invalid_updated_at_triggers.sql
```

### الخطوة الثالثة: `policies.sql`

نفّذ:

```text
supabase/policies.sql
```

هذا الملف خاص بالجداول الجديدة فقط، ويطبق:

- المستخدم يقرأ Profile الخاص به فقط.
- Super Admin يقرأ Profiles المستخدمين.
- لا يوجد UPDATE مباشر على Profiles من المتصفح.
- لا يوجد INSERT أو UPDATE أو DELETE مباشر على `role_permissions`.
- أدوار وصلاحيات القراءة متاحة للمستخدم النشط، دون منحه صلاحيات تعديل.

يجب تنفيذ هذا الملف بعد `functions.sql` لأن السياسات تعتمد على Helper Functions الموجودة فيه.

## 5. إنشاء أول مستخدم Super Admin

### الطريقة الموصى بها

1. نفّذ `schema.sql` و`functions.sql` و`policies.sql`.
2. افتح:

```text
Supabase Dashboard → Authentication → Users
```

3. اختر Add user.
4. أنشئ مستخدمًا بالبريد وكلمة مرور.
5. إذا كان تأكيد البريد الإلكتروني مفعلًا، قم بتأكيد المستخدم أو عطّل التأكيد مؤقتًا للاختبار.
6. Trigger النظام ينشئ Profile تلقائيًا.

تحقق من Profile:

```sql
select id, email, full_name, role, is_active
from public.profiles
order by created_at desc;
```

امنح المستخدم دور Super Admin من SQL Editor:

```sql
update public.profiles
set role = 'super_admin',
    is_active = true
where email = 'admin@example.com';
```

استبدل البريد بالبريد الحقيقي.

إذا كان Auth user موجودًا قبل تنفيذ `schema.sql`، فإن Backfill الموجود في نهاية الملف يحاول إنشاء Profile له تلقائيًا.

## 6. تسجيل الدخول إلى الواجهة

بعد منح الدور:

```bash
npm run dev
```

ثم افتح:

```text
/login
```

استخدم بريد وكلمة مرور Auth user.

بعد الدخول يجب أن تظهر:

- Dashboard.
- Sidebar حسب الدور.
- بيانات حقيقية من الجداول الأكاديمية.
- خيارات الإدارة المناسبة لـ Super Admin.

إذا ظهرت رسالة أن Profile غير موجود، تحقق من:

```sql
select * from public.profiles where email = 'admin@example.com';
```

## 7. نشر Edge Function للمستخدمين

صفحة `/users` تستطيع تعديل المستخدمين عبر RPC. أما دعوة مستخدم جديد فتحتاج Edge Function لأن إنشاء Auth user يتطلب Admin API.

الملف:

```text
supabase/functions/create-user/index.js
```

### تسجيل الدخول إلى Supabase CLI

استخدم Supabase CLI المثبت على جهازك:

```bash
supabase login
supabase link --project-ref axsxatnxnvhhcegdwoyi
```

اضبط Secrets. ضع Service Role Key في Secrets فقط:

```bash
supabase secrets set \
  SUPABASE_URL=https://axsxatnxnvhhcegdwoyi.supabase.co \
  SUPABASE_ANON_KEY=your-anon-or-publishable-key \
  SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

ثم انشر الدالة:

```bash
supabase functions deploy create-user
```

`SUPABASE_SERVICE_ROLE_KEY` لا يوضع في:

- `.env` الخاص بالواجهة.
- React code.
- Git repository.
- Browser local storage.

الدالة تتحقق من أن المستدعي:

- يملك جلسة صحيحة.
- لديه Profile نشط.
- دوره `super_admin`.

ثم تستخدم `inviteUserByEmail` وترسل دعوة للمستخدم وتنشئ Profile له.

## 8. ملف `academic-policies.sql`

الملف:

```text
supabase/academic-policies.sql
```

اختياري ولا يتم تشغيله ضمن الخطوات الأساسية.

يقوم بتفعيل RLS على الجداول الأكاديمية الحالية، ولذلك قد يمنع تطبيق Flutter من قراءة البيانات إذا كان يستخدم اتصالًا مجهولًا عبر `anon`.

لا تشغله قبل التأكد من أن تطبيق Flutter:

- يستخدم Supabase Auth.
- يرسل Access Token صحيحًا.
- يستطيع الحصول على Profile ودور مناسب.
- لديه صلاحيات قراءة في `role_permissions`.

إذا كان Flutter الحالي يعتمد على القراءة العامة بدون تسجيل دخول، فإن تشغيل هذا الملف سيؤدي غالبًا إلى رفض طلباته. اختبر في مشروع Staging أو بعد تجهيز Flutter أولًا.

## 9. اختبار الوظائف الأساسية

بعد تسجيل الدخول كـ Super Admin، اختبر بالترتيب:

1. فتح Dashboard.
2. فتح Buildings وإضافة مبنى ثم تعديله.
3. فتح Halls وإضافة قاعة مرتبطة بمبنى.
4. فتح Departments وLevels.
5. إنشاء Batch مرتبطة بقسم ومستوى.
6. فتح Subjects وإنشاء مادة رئيسية ومادة تابعة.
7. إضافة Instructor.
8. إنشاء Lecture.
9. إنشاء محاضرة بنفس القاعة واليوم والوقت، والتأكد من ظهور تعارض.
10. إلغاء محاضرة والتأكد من ظهور Badge ملغاة.
11. فتح Schedule والتأكد من العرض اليومي والأسبوعي.
12. فتح Reports.
13. تعديل الاسم من Settings.
14. تغيير المظهر إلى Dark ثم إعادة تحميل الصفحة.
15. دعوة مستخدم بعد نشر Edge Function.
16. إنشاء مستخدم Viewer والتأكد من عدم ظهور أزرار الإضافة والتعديل والحذف.

## 10. فهم مسارات الكتابة الآمنة

- تعديل الاسم الشخصي:

```text
Settings → update_my_profile()
```

- تعديل المستخدمين:

```text
Users → admin_update_profile()
```

- تعديل الصلاحيات:

```text
Roles → set_role_permission()
```

- فحص تعارض المحاضرات:

```text
Lectures → find_lecture_conflicts()
```

لا تمنح الواجهة صلاحية الكتابة المباشرة على Profiles أو Role Permissions.

## 11. تشخيص مشكلة CRUD وRLS

إذا ظهرت رسالة `Cannot coerce the result to a single JSON object` أو ظهرت رسالة نجاح بدون أن يتغير السجل، شغّل الملف التالي من SQL Editor:

```text
supabase/diagnostics.sql
```

هو ملف قراءة فقط ويفحص:

- حالة RLS لجدول `departments` والجداول الأكاديمية.
- السياسات الحالية.
- صلاحيات `anon` و`authenticated`.
- وجود السجل رقم 18.
- وجود RPCs المطلوبة.

### حالة Migration التي تم تشغيلها جزئيًا

إذا تم تشغيل النسخة التي توقفت عند تعليق `SCHEDULE RPC/trigger overrides`، فلا تعِد تشغيل ملف الجداول القديم ولا Migration الإصلاح القديمة. Migration المرحلة الأولى الحالية أدناه هي النسخة النهائية المتوافقة مع ذلك التنفيذ الجزئي، وتحتوي على تعريفات RPC/Trigger الخاصة بالمحاضرات والحجوزات والإلغاء المؤقت.

## 12. المشاكل الشائعة

### رسالة Profiles غير موجود

نفّذ `schema.sql` ثم `functions.sql` ثم `policies.sql`، ثم أعد تحميل الصفحة.

### لا يستطيع المستخدم الدخول بعد إنشاء Auth user

تحقق من:

```sql
select id, email, role, is_active
from public.profiles
where email = '...';
```

يجب أن يكون `is_active = true`، ويجب منح المستخدم دورًا مناسبًا.

### رسالة function does not exist

نفّذ `supabase/functions.sql` وتأكد من استخدام نفس أسماء RPC الموجودة في الملف.

### لا تظهر بيانات Dashboard

تحقق من:

- وجود Session صحيحة.
- وجود Profile.
- أن الحساب نشط.
- تشغيل `policies.sql`.
- عدم وجود خطأ RLS في Network أو Console.

### فشل دعوة مستخدم

تحقق من:

- نشر `create-user`.
- وجود `SUPABASE_SERVICE_ROLE_KEY` في Edge Function Secrets.
- أن المستدعي Super Admin.
- إعدادات Email Provider في Supabase.

### تعطل Flutter بعد تفعيل RLS

لا تستخدم `academic-policies.sql` مع Flutter مجهول الاتصال. يجب إما تجهيز Auth وPolicies في Flutter أو إبقاء الملف غير منفذ حتى الانتهاء من الترحيل.

## 12. مراجعة الملفات

- `supabase/inspection.md`: نتائج الفحص.
- `supabase/inspection.sql`: استعلامات فحص metadata.
- `supabase/schema.sql`: الجداول الجديدة والـ seed وTrigger.
- `supabase/functions.sql`: الدوال الأمنية وRPCs والفهارس.
- `supabase/policies.sql`: RLS للجداول الجديدة.
- `supabase/academic-policies.sql`: RLS اختيارية للجداول الحالية.
- `supabase/security-review.md`: التبرير الأمني والتصميمي.
