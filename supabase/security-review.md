# المراجعة الأمنية والتصميمية

## الحكم العام

ملاحظات المراجعة صحيحة في جوهرها، خصوصًا منع الكتابة المباشرة على `profiles` و`role_permissions`، وفصل RLS الجديدة عن RLS الخاصة بالجداول الأكاديمية المستخدمة بواسطة Flutter. التصميم المعدل يطبق ذلك دون حذف أو تعديل أو نقل أي صف من الجداول الأكاديمية.

## القرارات النهائية

### 1. Profiles

- `profiles.role` أصبح `FOREIGN KEY` إلى `roles(key)` بدل CHECK ثابت؛ بذلك يكون جدول `roles` مصدر الحقيقة الوحيد.
- لا يوجد `UPDATE` مباشر ممنوح لدور `authenticated` على `profiles`.
- المستخدم يحدّث اسمه فقط عبر `update_my_profile()`، والدالة تتحقق من الجلسة، وجود Profile نشط، الاسم بعد `trim`، وطول من 2 إلى 120 حرفًا.
- مدير النظام الأعلى يعدّل `full_name`, `role`, `department_id`, `is_active` فقط عبر `admin_update_profile()`، مع منع الحقول الإضافية ومنع تعطيل/تغيير دور نفسه ومنع إزالة آخر Super Admin نشط.
- القراءة في RLS: المستخدم يرى صفه فقط، وSuper Admin يرى جميع الصفوف.

### 2. Roles وPermissions

- لا توجد صلاحيات كتابة مباشرة على `roles`, `permissions`, أو `role_permissions`.
- تغيير رابط صلاحية يتم عبر `set_role_permission()` فقط، ولا يقبل إلا Super Admin نشطًا.
- لا يمكن تعديل مصفوفة `super_admin` لأن هذا الدور يتعامل معه `has_permission()` كصاحب صلاحية كاملة دائمًا.
- `role_permissions` يبقى قابلًا للتوسع دون تعديل جدول `profiles` عند إضافة دور جديد.

### 3. SECURITY DEFINER

كل دالة ذات صلاحيات أعلى:

- تستخدم `search_path = public, pg_temp`.
- يتم سحب EXECUTE من `public` و`anon`.
- يتم منح EXECUTE لـ `authenticated` فقط.
- تحتوي على فحص صريح للجلسة والحساب النشط والصلاحية المطلوبة.

`find_lecture_conflicts()` يسمح فقط بـ `lectures.create` عند الإنشاء أو `lectures.update` عند التعديل. يعيد نوع التعارض فقط، وليس بيانات محاضرات قسم آخر.

### 4. ENUM day_of_week

لم يتم تخمين اسم نوع ENUM لأنه غير ظاهر من مخطط PostgREST الذي تم فحصه. تستقبل الدالة قيمة `text` عند حد RPC، ثم تتحقق منها في `pg_enum` مقابل النوع الفعلي المرتبط بالعمود `lectures.day_of_week`. هذا يحقق التوافق مع النوع الحالي ويمنع قبول قيمة غير صحيحة دون اختراع اسم type.

### 5. التعارضات والفهارس

تم استبدال فكرة الفهرس المركب الواحد بثلاثة Partial Indexes مستقلة:

- `lectures_conflict_hall_idx`
- `lectures_conflict_instructor_idx`
- `lectures_conflict_batch_idx`

كلها تبدأ باليوم وبُعد التعارض وتستبعد المحاضرات الملغاة. هذا أنسب لأن الاستعلام ينفذ ثلاثة فروع مستقلة في `UNION ALL`؛ الفهرس السابق الذي يبدأ بـ hall ثم instructor ثم batch لا يخدم فرعي المدرس والدفعة بكفاءة بسبب قاعدة left-prefix في B-tree.

### 6. Department Manager

العلاقات الحالية تسمح بتطبيق العزل على:

- `batches.department_id`
- `lectures.batch_id -> batches.department_id`
- `departments.id`

ولا تسمح بعزل حقيقي للمواد أو المدرسين أو القاعات، لأن هذه الجداول لا تحتوي `department_id` ولا جدول ربط بالقسم. لذلك أصبح مدير القسم يقرأ هذه البيانات العامة فقط، وتبقى القاعات والمدرسون موارد مشتركة تستخدم في فحص التعارض العام.

### 7. Triggers والتوافق

- لا يوجد `DROP TRIGGER` عام.
- اسم Trigger الجديد هو `profiles_on_auth_user_created`.
- دالة الـ trigger اسمها `uhms_handle_new_auth_user`.
- يتم إنشاء Trigger النظام فقط عند عدم وجود نفس الاسم والجدول. إذا كان Trigger قديم باسم عام موجودًا، لا يتم حذفه.
- `schema.sql` لا يستخدم `DROP TABLE`, `TRUNCATE`, ولا أي عملية حذف بيانات.

## توزيع الملفات

- `schema.sql`: جداول جديدة، FK، grants قراءة فقط، seed للأدوار والصلاحيات، RLS الجديدة في وضع fail-closed، وTriggers النظام.
- `functions.sql`: helpers وRPCs الآمنة والفهارس الثلاثة.
- `policies.sql`: سياسات RLS للجداول الجديدة فقط.
- `academic-policies.sql`: سياسات اختيارية للجداول الأكاديمية الحالية. لا تشغّلها قبل اختبار توافق Flutter مع Supabase Auth.

## ترتيب التنفيذ

1. `schema.sql`
2. `functions.sql`
3. `policies.sql`
4. إنشاء/تأكيد أول Auth user ومنحه `super_admin` من SQL Editor.
5. اختبار الواجهة.
6. اختياريًا: `academic-policies.sql` بعد اختبار Flutter.

لم يتم تنفيذ أي SQL عن بعد أثناء هذه المراجعة.
