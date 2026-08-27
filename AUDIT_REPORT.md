# تقرير المراجعة الشاملة — University Hall Management System

تاريخ المراجعة: 25 أغسطس 2026

## نطاق المراجعة

تمت مراجعة المشروع الحالي، وليس إنشاء مشروع جديد، بما في ذلك:

- جميع Routes وPages وComponents.
- جميع Services واستدعاءات Supabase.
- AuthContext وThemeContext وReact Query.
- مسارات CRUD.
- دورة حياة المحاضرة.
- ملفات SQL الموجودة.
- اتصال Supabase ومشكلة 60 Connections.

تم تشغيل `npm install` ثم `npm run build`، كما تم إجراء اختبارات قراءة آمنة على REST API دون إنشاء أو تعديل أو حذف بيانات.

## نتيجة فحص Supabase الآمن

- طلبات القراءة المجهولة إلى `profiles`, `roles`, `permissions`, `role_permissions` مرفوضة، وهذا مؤشر جيد على أن السطح الجديد غير متاح للـ anon.
- طلبات القراءة المجهولة إلى الجداول الأكاديمية الحالية ما زالت تُرجع بيانات. هذا يحافظ على السلوك الحالي لتطبيق Flutter، لكنه يعني أن العزل الأمني للجداول الأكاديمية لم يتم إثباته من خلال RLS صارمة. لا يمكن استنتاج صلاحية الكتابة من اختبار القراءة فقط، لذلك يجب فحصها بحساب اختبار أو SQL catalog.
- طلبات RPC المجهولة مرفوضة.
- لم يتم تنفيذ أي INSERT أو UPDATE أو DELETE على Supabase أثناء المراجعة.

## المشكلات التي تم العثور عليها وإصلاحها

### 1. إعادة تفعيل المحاضرة كانت تتجاوز فحص التعارض — Critical — تم الإصلاح

قبل الإصلاح كان زر التفعيل يستدعي تحديث `canceled` مباشرة، لذلك كان ممكنًا إعادة تفعيل محاضرة تسبب تعارض Hall أو Instructor أو Batch.

الإصلاح:

- إضافة `set_lecture_canceled()` كـ SECURITY DEFINER RPC.
- التحقق من `lectures.cancel` ووجود Profile نشط.
- عند إعادة التفعيل، فحص القاعة والمدرس والدفعة قبل تغيير `canceled` إلى `false`.
- رفض العملية مع رسالة واضحة عند وجود تعارض.
- عدم حذف المحاضرة.
- إضافة Confirmation Dialog.
- تحديث Queries الخاصة بالمحاضرات والجدول والتقارير والـ Dashboard بعد النجاح.

لأن ملفات SQL الأساسية منفذة مسبقًا، يوجد Migration إضافي:

```text
supabase/migrations/20260825_add_lecture_lifecycle_rpc.sql
```

يجب تشغيله على Supabase مرة واحدة.

### 2. البحث في صفحات CRUD كان يتعطل لبعض الصفحات — High — تم الإصلاح

`CrudResourcePage` كان يتعامل مع كل `searchFields` كأنها دوال، بينما بعض الصفحات ترسل أسماء حقول نصية مثل `title` و`name`. هذا كان يؤدي إلى خطأ عند البحث.

تم إصلاحه لدعم:

```text
searchFields: ['title']
searchFields: [(row) => row.subject?.title]
```

### 3. تغييرات Role Permissions لم تكن تنعكس في الواجهة — High — تم الإصلاح

كان `AuthContext` يحمل Profile فقط، بينما `can()` يعتمد على صلاحيات ثابتة عند عدم وجود `profile.permissions`. لذلك تغيير `role_permissions` من صفحة الأدوار لا ينعكس دائمًا على Sidebar والأزرار.

تم إصلاح ذلك من خلال:

- تحميل صلاحيات الدور من `role_permissions` بعد تحميل Profile.
- إضافة `permissionsLoaded`.
- اعتماد `can()` على الصلاحيات القادمة من قاعدة البيانات عند توفرها.
- الإبقاء على fallback للبيئات القديمة فقط.

### 4. زر الإشعارات كان شكليًا — Medium — تم الإصلاح

تم تحويل الزر إلى قائمة فعلية تعرض آخر تحديثات المحاضرات والقاعات من Supabase عبر:

```text
src/services/notificationsService.js
```

### 5. فلتر اليوم لم يكن يطبق في جميع عروض Schedule — Medium — تم الإصلاح

كان فلتر اليوم يعمل في العرض اليومي فقط، ولا يطبق في عروض القاعة والمدرس والدفعة.

تم إصلاح ذلك بحيث يطبق اليوم على جميع العروض غير الأسبوعية.

### 6. تكرار طلبات metadata — Medium — تم الإصلاح

كانت صفحات القاعات والمواد والمدرسين والمحاضرات تستخدم Query Keys مختلفة لنفس metadata، مما يسبب طلبات متكررة.

تم توحيد Query Key إلى:

```text
['metadata']
```

ليتم استخدام cache مشترك لمدة 30 ثانية.

### 7. سباقات تحميل Profile — Medium — تم الإصلاح

كان `getSession()` و`onAuthStateChange()` قد يبدآن تحميل Profile في نفس الوقت، مما قد ينتج عنه نتيجة قديمة بعد تسجيل الخروج أو تبديل الحساب.

تم إضافة request generation guard داخل `AuthContext` لمنع تطبيق نتيجة طلب قديم.

## المشكلات المتبقية

### 1. RLS للجداول الأكاديمية الحالية تحتاج قرارًا تشغيليًا

الاختبار المجهول أظهر أن الجداول الأكاديمية الحالية قابلة للقراءة عبر anon. هذا قد يكون مقصودًا لتوافق Flutter، لكنه لا يثبت أن الكتابة محمية.

الملف المنفصل:

```text
supabase/academic-policies.sql
```

يفرض صلاحيات كاملة على مستوى قاعدة البيانات، لكنه قد يكسر Flutter إذا كان يعتمد على anon بدون Auth.

القرار المطلوب قبل الإنتاج:

- إذا كان Flutter للقراءة العامة فقط: أضف سياسة قراءة عامة، واجعل الكتابة Auth/RLS فقط.
- إذا كان Flutter يستخدم Auth: فعّل السياسات الحالية بعد اختبار شامل.
- لا تشغّل `academic-policies.sql` على الإنتاج دون اختبار Staging.

### 2. الاختبار Authenticated End-to-End يحتاج حساب اختبار

لم يتم إنشاء أو تعديل أي مستخدم على Supabase أثناء المراجعة. لذلك لا يمكن من بيئة المراجعة الحالية تنفيذ:

- Login فعلي.
- CRUD بصلاحيات Super Admin.
- اختبار Viewer وDepartment Manager.
- اختبار RPC عبر JWT حقيقي.
- اختبار Edge Function مع دعوة بريدية.

يجب تنفيذ مصفوفة الاختبار الموجودة في `supabase/SETUP.md` بحسابات اختبار منفصلة.

### 3. ENUM metadata

التطبيق يقرأ القيم المستخدمة من الجداول. هذا يغطي القيم الموجودة حاليًا، لكنه لا يضمن ظهور قيمة ENUM غير مستخدمة في أي صف. التحقق النهائي للقيم موجود في `inspection.sql` وداخل RPC فحص اليوم.

### 4. التوسع في البيانات

الـ CRUD الحالي يجلب القوائم ثم يطبق Pagination على العميل. هذا مناسب للحجم الحالي، لكنه يحتاج Pagination وFiltering من الخادم إذا أصبحت الجداول كبيرة جدًا.

## مصفوفة الوظائف

| الوظيفة | UI | Database / RPC | Permission | الحالة | ملاحظات |
|---|---|---|---|---|---|
| Buildings read | نعم | `buildings.select` | `buildings.view` | يعمل برمجيًا | يحتاج Auth/RLS للجداول الأكاديمية في الإنتاج |
| Buildings create | نعم | `insertRow('buildings')` | `buildings.create` | يعمل برمجيًا | Validation وToast موجودان |
| Buildings update | نعم | `updateRow('buildings')` | `buildings.update` | يعمل برمجيًا | يتم تحديث Query بعد النجاح |
| Buildings delete | نعم | `deleteRow('buildings')` | `buildings.delete` | يعمل برمجيًا | Confirmation وFK error handling |
| Halls read | نعم | Supabase + Building relation | `halls.view` | يعمل برمجيًا | الحالة تحسب من الحجز والمحاضرات |
| Halls create/update/delete | نعم | Supabase CRUD | create/update/delete | يعمل برمجيًا | فلاتر المبنى والدور والنوع والحالة |
| Departments CRUD | نعم | Supabase CRUD | department permissions | يعمل برمجيًا | الاختصار Unique من قاعدة البيانات |
| Levels CRUD | نعم | Supabase CRUD | level permissions | يعمل برمجيًا | علاقات الدفعات تمنع حذف المرتبط |
| Batches CRUD | نعم | Supabase + department/level FKs | batch permissions | يعمل برمجيًا | `department_abbr` يحسب من القسم |
| Subjects CRUD | نعم | Supabase + `parent_id` | subject permissions | يعمل برمجيًا | يمنع ربط المادة بنفسها |
| Instructors CRUD | نعم | Supabase CRUD | instructor permissions | يعمل برمجيًا | النوع يقرأ من metadata |
| Lecture create | نعم | conflict RPC ثم Supabase insert | `lectures.create` | يعمل بعد SQL الحالي | فحص Hall/Instructor/Batch ووقت صحيح |
| Lecture update | نعم | conflict RPC ثم Supabase update | `lectures.update` | يعمل بعد SQL الحالي | يستثني المحاضرة الحالية |
| Lecture cancel | نعم | `set_lecture_canceled(true)` | `lectures.cancel` | يحتاج Migration الجديد | لا يحذف، مع Confirmation |
| Lecture reactivate | نعم | `set_lecture_canceled(false)` | `lectures.cancel` | يحتاج Migration الجديد | يعيد فحص التعارضات |
| Lecture active/canceled filter | نعم | `canceled` | `lectures.view` | يعمل برمجيًا | Badge للحالتين |
| Schedule daily | نعم | `lectures` | `lectures.view` | يعمل برمجيًا | فلتر اليوم مطبق |
| Schedule weekly | نعم | `lectures` | `lectures.view` | يعمل برمجيًا | 7 أيام وعرض أفقي |
| Schedule by hall/instructor/batch | نعم | `lectures` | `lectures.view` | يعمل برمجيًا | فلتر اليوم يصلح بعد الإصلاح |
| Users read | نعم | `profiles.select` | Super Admin | يحتاج Auth test | القراءة محمية للجداول الجديدة |
| User invite | نعم | Edge Function `create-user` | Super Admin | يحتاج deploy/test | Service Role لا يوجد في Frontend |
| User role change | نعم | `admin_update_profile()` | Super Admin | يعمل بعد RPC | لا يسمح بتغيير الدور ذاتيًا |
| User department change | نعم | `admin_update_profile()` | Super Admin | يعمل بعد RPC | يتحقق من القسم |
| User enable/disable | نعم | `admin_update_profile()` | Super Admin | يعمل بعد RPC | يمنع تعطيل آخر Super Admin |
| Role permission change | نعم | `set_role_permission()` | Super Admin | يعمل بعد RPC | لا يمكن تعطيل صلاحيات Super Admin |
| Dashboard statistics | نعم | Supabase counts/relations | dashboard permission | يعمل برمجيًا | بدون Mock Data |
| Reports | نعم | Supabase lectures | `reports.view` | يعمل برمجيًا | aggregations حقيقية |
| Profile name update | نعم | `update_my_profile()` | authenticated active | يعمل بعد RPC | الاسم فقط |
| Password update | نعم | Supabase Auth | authenticated | يعمل برمجيًا | عبر `auth.updateUser` |
| Theme | نعم | localStorage | authenticated | يعمل | Light/Dark/System |

## مراجعة مشكلة 60 Connections

تم فحص `package.json` وملفات الاتصال:

- لا يوجد Prisma.
- لا يوجد `pg` أو PostgreSQL Client.
- لا يوجد `DATABASE_URL`.
- لا يوجد Node Backend أو NestJS.
- لا يوجد `connection_limit`.
- React يستخدم `@supabase/supabase-js` فقط.
- يوجد Supabase Client واحد في `src/lib/supabase.js`.
- لا توجد Realtime subscriptions إضافية بدون cleanup.
- Edge Function تنشئ Clients داخل كل Invocation، وهذا طبيعي لأنها Serverless وليست Pool PostgreSQL دائمًا.

لذلك لا ينبغي إضافة:

```text
connection_limit
port 6543
```

إلى `.env` الخاص بالواجهة. المتصفح يتصل عبر HTTPS إلى Supabase وليس باتصال PostgreSQL مباشر.

مشكلة 60 Connections يجب فحصها من:

- تطبيق Flutter.
- أي Backend آخر خارج هذا المستودع.
- Edge Functions الأخرى.
- Supabase Dashboard Database Metrics.
- `pg_stat_activity` بحساب إداري.

## الملفات التي تم تعديلها في هذه المراجعة

- `src/pages/lectures/Lectures.jsx`
- `src/services/lecturesService.js`
- `src/services/authService.js`
- `src/lib/permissions.js`
- `src/components/common/CrudResourcePage.jsx`
- `src/components/layout/Header.jsx`
- `src/services/notificationsService.js`
- `src/services/index.js`
- `src/pages/schedule/Schedule.jsx`
- `src/pages/dashboard/Dashboard.jsx`
- `src/pages/halls/Halls.jsx` عبر Query Key المشترك السابق
- `README.md`
- `supabase/SETUP.md`
- `supabase/functions.sql`
- `supabase/migrations/20260825_add_lecture_lifecycle_rpc.sql`
- `supabase/migrations/20260825_fix_departments_crud.sql`
- `supabase/migrations/20260825_fix_departments_updated_at_trigger.sql` (إصلاح خاص سابق بالأقسام)
- `supabase/migrations/20260825_fix_levels_crud.sql`
- `supabase/migrations/20260826_fix_batches_crud.sql`
- `supabase/migrations/20260826_fix_subjects_crud.sql`
- `supabase/migrations/20260826_fix_instructors_crud.sql`
- `supabase/migrations/20260826_fix_authenticated_academic_crud.sql` (Migration الشاملة الموصى بها)
- `supabase/migrations/20260825_fix_invalid_updated_at_triggers.sql`

## SQL المطلوب الآن

بما أن ملفات SQL الأساسية منفذة مسبقًا، لا تعِد تشغيل النظام من الصفر. شغّل Migration الخاصة بالوظيفة التي ظهرت فيها المشكلة:

```text
supabase/migrations/20260825_add_lecture_lifecycle_rpc.sql
supabase/migrations/20260825_fix_departments_crud.sql
supabase/migrations/20260825_fix_levels_crud.sql
supabase/migrations/20260826_fix_batches_crud.sql
supabase/migrations/20260826_fix_subjects_crud.sql
supabase/migrations/20260826_fix_instructors_crud.sql
supabase/migrations/20260826_fix_authenticated_academic_crud.sql
supabase/migrations/20260825_fix_invalid_updated_at_triggers.sql
```

هذه الملفات تضيف RPC أو grants أو Policies أو تنظف Triggerات معطوبة فقط، ولا تحذف أو تعدل أو تنقل أي صف من الجداول الأكاديمية.

إذا كانت بيئة Supabase لم تنفذ النسخة الأمنية الأحدث من `functions.sql`، راجع تعريفات الـ RPC في SQL Editor أولًا، ثم نفذ التحديث المطلوب فقط. لا تشغّل `academic-policies.sql` قبل اختبار Flutter.

## التقييم النهائي

- اكتمال Routes وComponents: جيد.
- اكتمال CRUD البرمجي: جيد.
- دورة حياة المحاضرة بعد Migration الجديد: جيدة.
- حماية الجداول الجديدة: جيدة حسب اختبارات anon الآمنة.
- حماية الجداول الأكاديمية: غير محسومة حتى اختبار RLS/Flutter.
- مشكلة Connections داخل هذا المشروع: لا يوجد مصدر مباشر لها.
- Build: ناجح.
- Authenticated End-to-End: يحتاج حسابات اختبار حقيقية.

التقييم الحالي:

```text
جاهز للتجربة الداخلية بعد تشغيل Migration المحاضرات.
ليس جاهزًا للإنتاج النهائي قبل اختبار جميع الأدوار وتحديد سياسة RLS للجداول الأكاديمية مع Flutter.
```
