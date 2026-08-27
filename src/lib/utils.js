import { clsx } from './vendor.js'

export function cn(...inputs) {
  return clsx(inputs)
}

export const DAY_OPTIONS = [
  { value: 'احد', label: 'الأحد', short: 'أحد' },
  { value: 'أثنين', label: 'الإثنين', short: 'إثنين' },
  { value: 'ثلاثاء', label: 'الثلاثاء', short: 'ثلاثاء' },
  { value: 'اربعاء', label: 'الأربعاء', short: 'أربعاء' },
  { value: 'خميس', label: 'الخميس', short: 'خميس' },
  { value: 'جمعة', label: 'الجمعة', short: 'جمعة' },
  { value: 'سبت', label: 'السبت', short: 'سبت' },
]

// These values are the values observed in the connected database. The metadata service
// merges them with any additional values returned by the live tables.
export const ENUM_OPTIONS = {
  floors: ['الدور الاول', 'الدور الثاني', 'الدور الثالث', 'الدور الرابع'],
  hallTypes: ['قاعة', 'مدرج', 'مرسم', 'معمل'],
  subjectTypes: ['نظري', 'عملي', 'تمارين'],
  instructorTypes: ['دكتور', 'استاذ', 'مهندس'],
  groups: ['الكل', 'المجموعة الاولى', 'المجموعة الثانية', 'المجموعة الثالثة'],
}

export const DAY_ORDER = DAY_OPTIONS.map((day) => day.value)

export function getDayLabel(value) {
  return DAY_OPTIONS.find((day) => day.value === value)?.label || value || '—'
}

export function getDayShortLabel(value) {
  return DAY_OPTIONS.find((day) => day.value === value)?.short || value || '—'
}

export function getTodayDbValue(date = new Date()) {
  return DAY_OPTIONS[date.getDay()]?.value || DAY_OPTIONS[0].value
}

export function getDayIndex(value) {
  const index = DAY_OPTIONS.findIndex((day) => day.value === value)
  return index === -1 ? 99 : index
}

export function formatTime(value) {
  if (!value) return '—'
  const [hourText, minuteText] = String(value).split(':')
  const hour = Number(hourText)
  const minute = minuteText ?? '00'
  if (Number.isNaN(hour)) return value
  const suffix = hour >= 12 ? 'م' : 'ص'
  const displayHour = hour % 12 || 12
  return `${String(displayHour).padStart(2, '0')}:${minute} ${suffix}`
}

export function formatTimeRange(start, end) {
  return `${formatTime(start)} — ${formatTime(end)}`
}

export function formatDate(value, options = {}) {
  if (!value) return '—'
  try {
    return new Intl.DateTimeFormat('ar-YE', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      ...options,
    }).format(new Date(value))
  } catch {
    return value
  }
}

export function formatRelativeDate(value) {
  if (!value) return '—'
  const date = new Date(value)
  const diff = Date.now() - date.getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return 'الآن'
  if (minutes < 60) return `منذ ${minutes} دقيقة`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `منذ ${hours} ساعة`
  const days = Math.floor(hours / 24)
  if (days < 7) return `منذ ${days} يوم`
  return formatDate(value)
}

export function timeToMinutes(value) {
  if (!value) return NaN
  const [hours, minutes] = String(value).split(':').map(Number)
  return hours * 60 + minutes
}

export function isValidTimeRange(start, end) {
  const startMinutes = timeToMinutes(start)
  const endMinutes = timeToMinutes(end)
  return Number.isFinite(startMinutes) && Number.isFinite(endMinutes) && startMinutes < endMinutes
}

export function rangesOverlap(newStart, newEnd, existingStart, existingEnd) {
  return timeToMinutes(newStart) < timeToMinutes(existingEnd) && timeToMinutes(newEnd) > timeToMinutes(existingStart)
}

export function normalizeText(value) {
  return String(value || '')
    .trim()
    .toLocaleLowerCase('ar')
    .replace(/[إأآ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
}

export function includesText(value, query) {
  if (!query) return true
  return normalizeText(value).includes(normalizeText(query))
}

export function getErrorMessage(error, fallback = 'حدث خطأ غير متوقع') {
  if (!error) return fallback
  if (typeof error === 'string') return error
  return error.message || error.error_description || error.details || fallback
}

export function getInitials(name = '') {
  const words = name.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return 'م'
  return words.slice(0, 2).map((word) => word[0]).join('').toUpperCase()
}

export function isReservationActiveNow(reservation, now = new Date()) {
  if (!reservation || reservation.status !== 'active') return false
  const dayMatches = reservation.reservation_date
    ? new Date(`${reservation.reservation_date}T00:00:00`).toDateString() === now.toDateString()
    : reservation.day_of_week === getTodayDbValue(now)
  if (!dayMatches) return false
  const current = now.getHours() * 60 + now.getMinutes()
  return current >= timeToMinutes(reservation.start_at) && current < timeToMinutes(reservation.end_at)
}

export function getLectureStatus(lecture, now = new Date()) {
  if (lecture?.canceled) return 'canceled'
  if (lecture?.day_of_week !== getTodayDbValue(now)) return 'upcoming'
  const current = now.getHours() * 60 + now.getMinutes()
  const start = timeToMinutes(lecture.start_at)
  const end = timeToMinutes(lecture.end_at)
  if (current >= start && current < end) return 'live'
  if (current < start) return 'upcoming'
  return 'ended'
}

export function getStatusLabel(status) {
  return {
    live: 'جارية الآن',
    upcoming: 'قادمة',
    ended: 'انتهت',
    canceled: 'ملغاة',
    active: 'نشطة',
    available: 'متاحة',
    occupied: 'مشغولة بمحاضرة',
    reserved: 'محجوزة',
    unavailable: 'غير متاحة للجدولة',
  }[status] || status || '—'
}

export function getStatusClass(status) {
  return {
    live: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400',
    upcoming: 'bg-blue-500/10 text-blue-600 dark:text-blue-400',
    ended: 'bg-slate-500/10 text-slate-600 dark:text-slate-400',
    canceled: 'bg-rose-500/10 text-rose-600 dark:text-rose-400',
    active: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400',
    available: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400',
    occupied: 'bg-amber-500/10 text-amber-600 dark:text-amber-400',
    reserved: 'bg-violet-500/10 text-violet-600 dark:text-violet-400',
    unavailable: 'bg-rose-500/10 text-rose-600 dark:text-rose-400',
  }[status] || 'bg-muted text-muted-foreground'
}

export function uniqueValues(items, key) {
  return [...new Set(items.map((item) => item?.[key]).filter(Boolean))]
}
