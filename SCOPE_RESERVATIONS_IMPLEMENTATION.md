# تنفيذ نطاقات مديري الأقسام والحجوزات والإلغاء المؤقت

## فحص ما قبل التنفيذ

تمت إعادة فحص قاعدة البيانات الحالية قبل التعديل:

- `department_levels` موجود من التنفيذ الجزئي السابق ويُعاد استخدامه.
- `department_manager_scopes` موجود ويُعاد استخدامه.
- `hall_reservations` موجود ويُمدد بإضافة `reservation_date` بدل إنشاء جدول مكرر.
- `lecture_occurrence_overrides` غير موجود؛ لذلك أُضيف كجدول جديد لأنه ضروري لتمثيل إلغاء يوم واحد بدون تعديل المحاضرة الأسبوعية.
- القاعات الحالية 34 وقيمة `booking` الحالية كلها `false`.
- المحاضرات الحالية تعتمد على `day_of_week` ولا تحتوي على تاريخ occurrence.

## نطاق مدير القسم

- `department_levels` يثبت المستوى التابع للقسم.
- `department_manager_scopes` يحدد من يدير ماذا.
- `level_id` محدد يعني مستوى واحد.
- عدة صفوف تعني عدة مستويات.
- `level_id = null` يعني جميع المستويات المرتبطة بالقسم، والـScope صريح وملزم.
- مدير القسم بلا Scope لا يحصل على بيانات الأقسام/المستويات/الدفعات/المحاضرات، أي أن السلوك Fail-Closed.
- لا يمكن إنشاء Scope لقسم مختلف عن `profiles.department_id`، ولا لمستوى غير موجود في `department_levels` النشط.
- يوجد تحقق قاعدة بيانات مستقل على كتابة `department_manager_scopes`، وليس اعتمادًا على تحقق الواجهة فقط.
- تتم حماية departments/levels/batches/lectures عبر Restrictive RLS.
- لا يتم حذف Policies قديمة بأسماء متوقعة؛ تضاف طبقة Restrictive namespaced حتى لا تتجاوزها Policy permissive قديمة.

## الإلغاء المؤقت

تبقى `lectures` كـ Master Weekly Schedule.

الإلغاء لتاريخ محدد يُحفظ في:

```text
lecture_occurrence_overrides
```

ولا يغيّر `lectures.canceled`.

- `canceled` في lectures: إلغاء السلسلة الأسبوعية كاملة.
- override: إلغاء occurrence بتاريخ واحد.
- `set_lecture_occurrence_canceled()` يتحقق من اليوم والنطاق والتعارض عند إعادة التفعيل.
- يوجد History مستقل لـ occurrence.

## حجوزات القاعات

تم تمديد جدول `hall_reservations` الموجود لدعم:

- حجز أسبوعي عبر `day_of_week`.
- حجز مؤقت بتاريخ محدد عبر `reservation_date`.
- وقت البداية والنهاية.
- active/canceled.
- السبب والملاحظات.
- created_by/updated_by.
- `department_id` و`level_id` للحجوزات المؤقتة التي ينشئها Department Manager ضمن Scope.

لا يتم تحويل `reservation_date` إلى `day_of_week` عند فحص المحاضرات.

حجز اليوم الواحد يتعارض مع occurrence الفعلي لذلك التاريخ فقط، وإذا كانت المحاضرة الأسبوعية ملغاة لذلك التاريخ عبر override، يمكن إنشاء الحجز.

إذا كان الحجز موجودًا أولًا ثم حاول المستخدم إنشاء محاضرة أسبوعية تتعارض معه، ترفض قاعدة البيانات العملية؛ لأن السلسلة الأسبوعية كما هي في المخطط الحالي لا تملك تاريخ بداية/نهاية.

## booking

تم اعتماد:

```text
booking = true  → القاعة غير متاحة للجدولة
booking = false → القاعة قابلة للجدولة عند عدم وجود تعارض
```

يُفرض ذلك داخل:

- `save_lecture_atomic()`.
- `set_lecture_canceled_with_reason()`.
- `uhms_lectures_conflict_guard`.
- `uhms_phase1_hall_booking_lock` عند تغيير `halls.booking`.
- `save_hall_reservation()`.
- `set_hall_reservation_status()`.
- `uhms_phase1_hall_reservation_conflict_guard` على جدول `hall_reservations`، لضمان عدم تجاوز المنع بكتابة مباشرة.

## الواجهة

تمت إضافة/تحديث:

```text
/reservations
/department-levels
```

كما تم إضافة تبويب داخل صفحة المحاضرات:

```text
المحاضرات الأسبوعية
حجز قاعة
```

الواجهة تدعم:

- حجز أسبوعي أو حجز ليوم واحد.
- سبب وملاحظات.
- إلغاء/تفعيل الحجز.
- إلغاء occurrence من Schedule بتاريخ محدد.
- فتح المحاضرة للتعديل.
- عرض History.
- حالات القاعة: متاحة، مشغولة، محجوزة، غير متاحة.

## Migration

للتثبيت الحالي، بعد تطبيق Migrations السابقة، تم تشغيل:

```text
supabase/migrations/20260827_phase1_scope_occurrence_reservations.sql
```

ولتفعيل إدارة Department Manager للحجوزات المؤقتة ضمن Scope، تم تطبيق الإضافة:

```text
supabase/migrations/20260830_department_manager_temporary_reservation_scope.sql
```

هذه الإضافة تعيد استخدام `hall_reservations` ومفاتيح الصلاحيات الموجودة، وتضيف فقط أعمدة Scope اختيارية للحجوزات العامة القديمة. تمنح Department Manager `hall_reservations.create/update/cancel`، لكن RPC وRLS يقصرانه على Temporary Reservation بتاريخ محدد ومستوى موجود داخل Scope؛ ولا تمنحه الحجز الأسبوعي أو `lectures.cancel_series`.

## التحقق البرمجي

تم تشغيل:

```bash
npm install --no-audit --no-fund
npm run build
```

ونجح البناء بدون أخطاء. يوجد فقط تحذير حجم Bundle من Recharts.

## التحقق الفعلي بعد تطبيق Migration

تم التحقق بحساب Super Admin مصادق فعليًا، وشملت الاختبارات:

- توفر الجداول والـRPCs الجديدة.
- رفض Scope لقسم مختلف أو لحساب ليس Department Manager.
- نجاح Scope لمستوى واحد/عدة مستويات/جميع المستويات ثم إعادة Scope الأصلي.
- رفض الحجز المؤقت عند وجود occurrence نشط.
- إلغاء occurrence يدويًا ثم نجاح الحجز في التاريخ المحدد.
- بقاء `lectures.canceled = false` وعدم الإلغاء التلقائي للمحاضرة.
- حفظ الحجز المؤقت بتاريخ صحيح مع بقاء `day_of_week = null`.
- نجاح الحجز الأسبوعي ورفض الحجز الأسبوعي المتداخل.
- رفض الجدولة والحجز عند `halls.booking = true` ثم إعادة القيمة الأصلية.
- رفض الكتابة المباشرة المصادق عليها للحجوزات وScopes وoccurrence وتعارضات المحاضرات.
- النتيجة: 47 اختبارًا تكامليًا ناجحًا، ثم اختبارات تكميلية لإعادة التفعيل والتعديل وفحص التاريخ المطابق وغير المطابق؛ أي 55 تحققًا ناجحًا، دون تغيير أي صف في جدول المحاضرات.

تم التحقق أيضًا بجلسة Department Manager فعلية مرتبطة بالقسم 1 والمستوى 2: ظهرت لها بيانات القسم والمستوى والدفعات والمحاضرات ضمن Scope فقط، ورُفضت محاولات الوصول والتعديل خارج Scope، ونجح إلغاء occurrence وإنشاء وإدارة Temporary Reservation داخل Scope، بينما رُفض إلغاء السلسلة الأسبوعية. بعد الاختبار أُعيد occurrence إلى حالته الأصلية.

تركت الحجوزات الاختبارية في حالة `canceled` وسجلات occurrence في جدول التاريخ بعلامة `UHMS_PHASE1_AUTOTEST`؛ لم أحذف سجلات التاريخ حفاظًا على الـAudit Trail.