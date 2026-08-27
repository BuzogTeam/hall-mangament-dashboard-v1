# تقرير فحص قاعدة البيانات الحالية

تم فحص البيانات الحالية عبر PostgREST في مشروع Supabase المعرّف في `.env` بتاريخ 24 أغسطس 2026. كما أُضيف `inspection.sql` لفحص الـ catalog من SQL Editor؛ فهذه التفاصيل (الـ enum والـ RLS والـ functions) لا يعرضها المفتاح publishable عبر PostgREST.

## الجداول الموجودة

- `buildings`: 4 سجلات، الاسم في `title`.
- `halls`: 34 سجلًا، والعلاقة `building_id -> buildings.id`.
- `departments`: 8 سجلات، والاختصار `abbreviation` فريد.
- `levels`: 5 سجلات.
- `batches`: 40 سجلًا، العلاقات `department_id -> departments.id` و`level_id -> levels.id`، إضافة إلى `department_abbr -> departments.abbreviation`.
- `subjects`: 179 سجلًا، والعلاقة الذاتية `parent_id -> subjects.id`.
- `instructors`: 166 سجلًا.
- `lectures`: 36 سجلًا، مع العلاقات إلى `subjects`, `halls`, `instructors`, `batches`.
- لم تكن الجداول `profiles`, `roles`, `permissions`, `role_permissions` موجودة عند الفحص.

## القيم الفعلية المرصودة من الـ ENUM

القيم التالية مأخوذة من السجلات الحالية، وليست بيانات Mock:

- `floors`: `الدور الاول`, `الدور الثاني`, `الدور الثالث`, `الدور الرابع`.
- `class_type`: `قاعة`, `مدرج`, `مرسم`, `معمل`.
- `subject_type`: `نظري`, `عملي`, `تمارين`.
- `instructor_type`: `دكتور`, `استاذ`, `مهندس`.
- `groups`: `الكل`, `المجموعة الاولى`, `المجموعة الثانية`, `المجموعة الثالثة`.
- `day_of_week` المرصود: `احد`, `أثنين`, `ثلاثاء`, `اربعاء`, `سبت`.

يستخدم التطبيق خدمة `metadataService` لقراءة القيم من السجلات الفعلية عند التشغيل، مع القيم المرصودة كخيارات احتياطية لأن PostgREST لا يتيح قراءة قيم enum غير المستخدمة في سجل.

## ملاحظات سلامة البيانات

- وُجدت محاضرات ملغاة (`canceled = true`) وعددها 6، والتطبيق يحافظ عليها ولا يحذفها.
- وُجد تعارض قاعة موجود مسبقًا في البيانات الحالية؛ لذلك لم أضف trigger يكسر البيانات الحالية. أُضيفت دالة فحص تعارض اختيارية في `functions.sql`، كما أن الواجهة تفحص القاعة والمدرس والدفعة قبل كل إنشاء أو تعديل.
- `supabase/schema.sql` يضيف جداول النظام فقط، ويفعّل RLS الجديدة بوضع fail-closed، ولا يغير الجداول الأكاديمية الحالية.
- `supabase/functions.sql` يحتوي helper functions وRPCs التي تمنع الكتابة المباشرة وتتحقق من صلاحية المستخدم والمدخلات.
- `supabase/policies.sql` يخص RLS للجداول الجديدة فقط.
- `supabase/academic-policies.sql` Migration أمنية منفصلة للجداول الأكاديمية الحالية. راجع توافقها مع تطبيق Flutter قبل تفعيلها؛ تفعيل RLS سيمنع وصول العميل المجهول ما لم يكن Flutter يستخدم Supabase Auth والسياسات المناسبة.
- النسخة الجديدة لا تستخدم اسم Trigger عام؛ Trigger النظام اسمه `profiles_on_auth_user_created` ولا يتم حذف Triggerات أخرى.
