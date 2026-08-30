export const ROLE_KEYS = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  SCHEDULE_MANAGER: 'schedule_manager',
  DEPARTMENT_MANAGER: 'department_manager',
  VIEWER: 'viewer',
}

export const ROLE_LABELS = {
  super_admin: 'مدير النظام الأعلى',
  admin: 'مدير',
  schedule_manager: 'مسؤول الجداول',
  department_manager: 'مدير قسم',
  viewer: 'مشاهد',
}

export const ROLE_DESCRIPTIONS = {
  super_admin: 'صلاحيات كاملة على جميع أجزاء النظام',
  admin: 'إدارة البيانات الأكاديمية والمرافق والجداول',
  schedule_manager: 'إدارة المحاضرات والجداول والقاعات المرتبطة',
  department_manager: 'إدارة بيانات قسمه ومحاضراته',
  viewer: 'الوصول للقراءة فقط',
}

export const PERMISSIONS = [
  ['dashboard.view', 'عرض لوحة التحكم'],
  ['buildings.view', 'عرض المباني'],
  ['buildings.create', 'إضافة المباني'],
  ['buildings.update', 'تعديل المباني'],
  ['buildings.delete', 'حذف المباني'],
  ['halls.view', 'عرض القاعات'],
  ['halls.create', 'إضافة القاعات'],
  ['halls.update', 'تعديل القاعات'],
  ['halls.delete', 'حذف القاعات'],
  ['hall_reservations.view', 'عرض حجوزات القاعات'],
  ['hall_reservations.create', 'إنشاء حجوزات القاعات'],
  ['hall_reservations.update', 'تعديل حجوزات القاعات'],
  ['hall_reservations.cancel', 'إلغاء حجوزات القاعات'],
  ['departments.view', 'عرض الأقسام'],
  ['departments.create', 'إضافة الأقسام'],
  ['departments.update', 'تعديل الأقسام'],
  ['departments.delete', 'حذف الأقسام'],
  ['levels.view', 'عرض المستويات'],
  ['levels.create', 'إضافة المستويات'],
  ['levels.update', 'تعديل المستويات'],
  ['levels.delete', 'حذف المستويات'],
  ['batches.view', 'عرض الدفعات'],
  ['batches.create', 'إضافة الدفعات'],
  ['batches.update', 'تعديل الدفعات'],
  ['batches.delete', 'حذف الدفعات'],
  ['subjects.view', 'عرض المواد'],
  ['subjects.create', 'إضافة المواد'],
  ['subjects.update', 'تعديل المواد'],
  ['subjects.delete', 'حذف المواد'],
  ['instructors.view', 'عرض المدرسين'],
  ['instructors.create', 'إضافة المدرسين'],
  ['instructors.update', 'تعديل المدرسين'],
  ['instructors.delete', 'حذف المدرسين'],
  ['lectures.view', 'عرض المحاضرات'],
  ['lectures.create', 'إضافة المحاضرات'],
  ['lectures.update', 'تعديل المحاضرات'],
  ['lectures.cancel_series', 'إلغاء السلسلة الأسبوعية'],
  ['lectures.cancel_occurrence', 'إلغاء محاضرة لتاريخ محدد'],
  ['lectures.cancel', 'إلغاء المحاضرات (توافق قديم)'],
  ['users.view', 'عرض المستخدمين'],
  ['users.manage', 'إدارة المستخدمين'],
  ['roles.view', 'عرض الأدوار والصلاحيات'],
  ['roles.manage', 'إدارة الأدوار والصلاحيات'],
  ['reports.view', 'عرض التقارير'],
  ['settings.view', 'عرض الإعدادات'],
]

const allCatalog = PERMISSIONS.filter(([key]) => !key.startsWith('users.') && !key.startsWith('roles.')).map(([key]) => key)

export const ROLE_PERMISSIONS = {
  super_admin: PERMISSIONS.map(([key]) => key),
  admin: allCatalog.filter((key) => !key.startsWith('dashboard.') || key === 'dashboard.view'),
  schedule_manager: [
    'dashboard.view', 'halls.view', 'hall_reservations.view', 'hall_reservations.create', 'hall_reservations.update', 'hall_reservations.cancel', 'lectures.view', 'lectures.create', 'lectures.update', 'lectures.cancel_series', 'lectures.cancel_occurrence', 'lectures.cancel', 'reports.view', 'settings.view',
  ],
  department_manager: [
    'dashboard.view', 'departments.view', 'levels.view', 'batches.view', 'batches.create', 'batches.update', 'subjects.view', 'instructors.view', 'halls.view', 'hall_reservations.view', 'hall_reservations.create', 'hall_reservations.update', 'hall_reservations.cancel', 'lectures.view', 'lectures.create', 'lectures.update', 'lectures.cancel_occurrence', 'reports.view', 'settings.view',
  ],
  viewer: [
    'dashboard.view', 'buildings.view', 'halls.view', 'departments.view', 'levels.view', 'batches.view', 'subjects.view', 'instructors.view', 'lectures.view', 'reports.view', 'settings.view',
  ],
}

export function normalizeRole(role) {
  const value = String(role || '').trim().toLowerCase()
  const aliases = {
    'super admin': 'super_admin',
    'superadmin': 'super_admin',
    'مدير النظام الأعلى': 'super_admin',
    'مدير النظام': 'super_admin',
    'مسؤول الجداول': 'schedule_manager',
    'مدير قسم': 'department_manager',
    'مشاهد': 'viewer',
  }
  return aliases[value] || value || 'viewer'
}

export function getRoleLabel(role) {
  const key = normalizeRole(role)
  return ROLE_LABELS[key] || role || 'غير محدد'
}

export function getRoleDescription(role) {
  return ROLE_DESCRIPTIONS[normalizeRole(role)] || 'صلاحيات مخصصة'
}

export function can(profile, permission) {
  if (!profile) return false
  const role = normalizeRole(profile.role)
  if (role === ROLE_KEYS.SUPER_ADMIN) return true
  if (profile.permissionsLoaded) return Array.isArray(profile.permissions) && profile.permissions.includes(permission)
  if (Array.isArray(profile.permissions)) return profile.permissions.includes(permission)
  return ROLE_PERMISSIONS[role]?.includes(permission) || false
}

export function isSuperAdmin(profile) {
  return normalizeRole(profile?.role) === ROLE_KEYS.SUPER_ADMIN
}

export function isDepartmentManager(profile) {
  return normalizeRole(profile?.role) === ROLE_KEYS.DEPARTMENT_MANAGER
}

export function canManage(profile, resource) {
  return can(profile, `${resource}.create`) || can(profile, `${resource}.update`)
}
