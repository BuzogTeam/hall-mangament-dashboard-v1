# تنفيذ نطاقات مديري الأقسام وحجوزات القاعات

## Preflight

قبل التنفيذ تم فحص الكود وقاعدة Supabase للقراءة فقط:

- `profiles` الحالية: Super Admin ومستخدمان Viewer، ولا يوجد Department Manager حاليًا.
- جميع قيم `halls.booking` الحالية وعددها 34 كانت `false`.
- `department_manager_scopes` غير موجود قبل هذه الإضافة.
- `hall_reservations` غير موجود قبل هذه الإضافة.
- `save_lecture_atomic`, `set_lecture_canceled_with_reason`, و`find_all_lecture_conflicts` موجودة من Migration الجدول السابقة.

## نطاق مدير القسم

الجداول:

```text
department_levels
department_manager_scopes
```

- `department_levels` يثبت أن المستوى تابع للقسم.
- `level_id = null`: جميع المستويات المرتبطة بالقسم.
- `level_id` محدد: مستوى واحد.
- عدة صفوف: عدة مستويات.
- المستخدم القديم الذي لديه `profiles.department_id` ولا يملك Scope يستمر كمدير كامل لقسمه، للحفاظ على التوافق.

تم إضافة:

- `department_manager_scope_allowed()`.
- `department_manager_level_allowed()`.
- `admin_set_department_manager_scopes()`.
- `admin_update_profile_with_scopes()`.

تم تحديث RLS للـ `departments`, `levels`, `batches`, `lectures` لتستخدم النطاق.

## حجوزات القاعات

جدول:

```text
hall_reservations
```

يدعم:

- حجز أسبوعي متكرر حسب `day_of_week`.
- `hall_id`.
- وقت البداية والنهاية.
- `active/canceled`.
- السبب والملاحظات.
- المستخدم المنشئ والمعدل.

تم إضافة:

- `find_hall_reservation_conflicts()`.
- `save_hall_reservation()`.
- `set_hall_reservation_status()`.

الحماية تمنع:

- حجزين متداخلين لنفس القاعة.
- الحجز مع محاضرة نشطة.
- الحجز في قاعة `booking = true`.
- إعادة تفعيل حجز متعارض.

## booking

تم اعتماد:

```text
booking = true  → القاعة غير متاحة للجدولة
booking = false → القاعة قابلة للجدولة عند عدم وجود حجز زمني أو محاضرة
```

تم إدخال الفحص في:

- `save_lecture_atomic()`.
- `set_lecture_canceled_with_reason()`.
- `uhms_lectures_conflict_guard`.

## الواجهة

تم إضافة:

```text
/reservations
```

وتحتوي على:

- عرض الحجوزات الأسبوعية.
- إنشاء حجز أسبوعي.
- تعديل الحجز.
- إلغاء/تفعيل الحجز.
- فلاتر القاعة والحالة.
- أسباب وملاحظات.

تم تحديث:

- Halls status لتمييز `available`, `occupied`, `reserved`, `unavailable`.
- Dashboard لإظهار غير المتاحة والمحجوزة والمشغولة منفصلة.
- Users لإدارة نطاقات Department Manager.
- Edge Function لدعم scopes عند دعوة مدير قسم.

## Migration

للتثبيت الحالي شغّل:

```text
supabase/migrations/20260826_scopes_and_hall_reservations.sql
```

لم يتم تنفيذها عن بعد بواسطة Agent لأن المفتاح المتاح للواجهة Publishable/Auth ولا يملك صلاحية DDL. الملف غير تدميري ولا يحذف البيانات.

## التحقق

- `npm run build` ناجح.
- Migration قابلة للتحليل النحوي PostgreSQL.
- لا توجد تغييرات على أعمدة الجداول الأكاديمية.
- لا توجد صلاحيات كتابة مباشرة للمستخدمين على scopes أو reservations؛ الكتابة عبر RPC.
