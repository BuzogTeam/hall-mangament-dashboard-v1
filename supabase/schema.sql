-- University Hall Management System: profiles, roles and permissions.
-- Safe, additive migration: it does not DROP/TRUNCATE/ALTER any academic table.
-- Run this file before functions.sql and policies.sql.

create table if not exists public.roles (
  key text primary key,
  label_ar text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  key text primary key,
  label_ar text not null,
  resource text not null,
  action text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  -- roles.key is the single source of truth for valid roles.
  role text not null default 'viewer' references public.roles(key),
  department_id bigint references public.departments(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_key text not null references public.roles(key) on delete cascade,
  permission_key text not null references public.permissions(key) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_key, permission_key)
);

-- If an earlier local version created profiles with the old static CHECK,
-- replace only that named constraint with the role FK. No rows are deleted.
do $$
begin
  if to_regclass('public.profiles') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.profiles'::regclass
         and conname = 'profiles_role_fkey'
     ) then
    alter table public.profiles drop constraint if exists profiles_role_check;
    alter table public.profiles
      add constraint profiles_role_fkey foreign key (role) references public.roles(key);
  end if;
end;
$$;

create index if not exists profiles_department_id_idx on public.profiles(department_id);
create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists role_permissions_permission_idx on public.role_permissions(permission_key);

grant usage on schema public to authenticated;

-- Authenticated clients can read authorization metadata and profiles through RLS,
-- but cannot write any of these tables directly. Writes go through SECURITY DEFINER
-- RPCs in functions.sql or the server-only Edge Function.
revoke all on public.profiles, public.roles, public.permissions, public.role_permissions from anon;
revoke all on public.profiles, public.roles, public.permissions, public.role_permissions from authenticated;
grant select on public.profiles, public.roles, public.permissions, public.role_permissions to authenticated;

-- Fail closed for the new tables as soon as they are created. The explicit policies
-- are installed by policies.sql; until then, no authenticated row is exposed.
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;

insert into public.roles(key, label_ar, description) values
  ('super_admin', 'مدير النظام الأعلى', 'صلاحيات كاملة على جميع أجزاء النظام'),
  ('admin', 'مدير', 'إدارة البيانات الأكاديمية والمرافق والجداول'),
  ('schedule_manager', 'مسؤول الجداول', 'إدارة المحاضرات والجداول والقاعات المرتبطة'),
  ('department_manager', 'مدير قسم', 'إدارة بيانات قسمه ومحاضراته'),
  ('viewer', 'مشاهد', 'الوصول للقراءة فقط')
on conflict (key) do update set label_ar = excluded.label_ar, description = excluded.description;

insert into public.permissions(key, label_ar, resource, action) values
  ('dashboard.view', 'عرض لوحة التحكم', 'dashboard', 'view'),
  ('buildings.view', 'عرض المباني', 'buildings', 'view'),
  ('buildings.create', 'إضافة المباني', 'buildings', 'create'),
  ('buildings.update', 'تعديل المباني', 'buildings', 'update'),
  ('buildings.delete', 'حذف المباني', 'buildings', 'delete'),
  ('halls.view', 'عرض القاعات', 'halls', 'view'),
  ('halls.create', 'إضافة القاعات', 'halls', 'create'),
  ('halls.update', 'تعديل القاعات', 'halls', 'update'),
  ('halls.delete', 'حذف القاعات', 'halls', 'delete'),
  ('hall_reservations.view', 'عرض حجوزات القاعات', 'hall_reservations', 'view'),
  ('hall_reservations.create', 'إنشاء حجوزات القاعات', 'hall_reservations', 'create'),
  ('hall_reservations.update', 'تعديل حجوزات القاعات', 'hall_reservations', 'update'),
  ('hall_reservations.cancel', 'إلغاء حجوزات القاعات', 'hall_reservations', 'cancel'),
  ('departments.view', 'عرض الأقسام', 'departments', 'view'),
  ('departments.create', 'إضافة الأقسام', 'departments', 'create'),
  ('departments.update', 'تعديل الأقسام', 'departments', 'update'),
  ('departments.delete', 'حذف الأقسام', 'departments', 'delete'),
  ('levels.view', 'عرض المستويات', 'levels', 'view'),
  ('levels.create', 'إضافة المستويات', 'levels', 'create'),
  ('levels.update', 'تعديل المستويات', 'levels', 'update'),
  ('levels.delete', 'حذف المستويات', 'levels', 'delete'),
  ('batches.view', 'عرض الدفعات', 'batches', 'view'),
  ('batches.create', 'إضافة الدفعات', 'batches', 'create'),
  ('batches.update', 'تعديل الدفعات', 'batches', 'update'),
  ('batches.delete', 'حذف الدفعات', 'batches', 'delete'),
  ('subjects.view', 'عرض المواد', 'subjects', 'view'),
  ('subjects.create', 'إضافة المواد', 'subjects', 'create'),
  ('subjects.update', 'تعديل المواد', 'subjects', 'update'),
  ('subjects.delete', 'حذف المواد', 'subjects', 'delete'),
  ('instructors.view', 'عرض المدرسين', 'instructors', 'view'),
  ('instructors.create', 'إضافة المدرسين', 'instructors', 'create'),
  ('instructors.update', 'تعديل المدرسين', 'instructors', 'update'),
  ('instructors.delete', 'حذف المدرسين', 'instructors', 'delete'),
  ('lectures.view', 'عرض المحاضرات', 'lectures', 'view'),
  ('lectures.create', 'إضافة المحاضرات', 'lectures', 'create'),
  ('lectures.update', 'تعديل المحاضرات', 'lectures', 'update'),
  ('lectures.cancel', 'إلغاء المحاضرات', 'lectures', 'cancel'),
  ('users.view', 'عرض المستخدمين', 'users', 'view'),
  ('users.manage', 'إدارة المستخدمين', 'users', 'manage'),
  ('roles.view', 'عرض الأدوار والصلاحيات', 'roles', 'view'),
  ('roles.manage', 'إدارة الأدوار والصلاحيات', 'roles', 'manage'),
  ('reports.view', 'عرض التقارير', 'reports', 'view'),
  ('settings.view', 'عرض الإعدادات', 'settings', 'view')
on conflict (key) do update set label_ar = excluded.label_ar, resource = excluded.resource, action = excluded.action;

-- Super Admin owns the complete matrix; the UI keeps the super_admin role read-only
-- because has_permission() always treats it as fully authorized.
insert into public.role_permissions(role_key, permission_key)
select 'super_admin', key from public.permissions
on conflict do nothing;

insert into public.role_permissions(role_key, permission_key)
select 'admin', key from public.permissions
where key not like 'users.%' and key not like 'roles.%'
on conflict do nothing;

insert into public.role_permissions(role_key, permission_key) values
  ('schedule_manager', 'dashboard.view'), ('schedule_manager', 'halls.view'),
  ('schedule_manager', 'hall_reservations.view'), ('schedule_manager', 'hall_reservations.create'),
  ('schedule_manager', 'hall_reservations.update'), ('schedule_manager', 'hall_reservations.cancel'),
  ('schedule_manager', 'lectures.view'), ('schedule_manager', 'lectures.create'),
  ('schedule_manager', 'lectures.update'), ('schedule_manager', 'lectures.cancel'),
  ('schedule_manager', 'reports.view'), ('schedule_manager', 'settings.view'),
  ('department_manager', 'dashboard.view'), ('department_manager', 'departments.view'),
  ('department_manager', 'levels.view'), ('department_manager', 'batches.view'),
  ('department_manager', 'batches.create'), ('department_manager', 'batches.update'),
  ('department_manager', 'subjects.view'), ('department_manager', 'instructors.view'),
  ('department_manager', 'halls.view'), ('department_manager', 'hall_reservations.view'), ('department_manager', 'lectures.view'),
  ('department_manager', 'lectures.create'), ('department_manager', 'lectures.update'),
  ('department_manager', 'lectures.cancel'), ('department_manager', 'reports.view'),
  ('department_manager', 'settings.view'),
  ('viewer', 'dashboard.view'), ('viewer', 'buildings.view'), ('viewer', 'halls.view'),
  ('viewer', 'hall_reservations.view'), ('viewer', 'departments.view'), ('viewer', 'levels.view'), ('viewer', 'batches.view'),
  ('viewer', 'subjects.view'), ('viewer', 'instructors.view'), ('viewer', 'lectures.view'),
  ('viewer', 'reports.view'), ('viewer', 'settings.view')
on conflict do nothing;

create or replace function public.uhms_set_updated_at()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.uhms_set_updated_at() from public, anon, authenticated;

-- Create only our trigger if it does not exist. This never removes an unrelated
-- trigger from auth.users or from profiles.
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'profiles_set_updated_at'
      and tgrelid = 'public.profiles'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.uhms_set_updated_at()';
  end if;
end;
$$;

create or replace function public.uhms_handle_new_auth_user()
returns trigger
security definer
set search_path = public, pg_temp
language plpgsql
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

revoke all on function public.uhms_handle_new_auth_user() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'profiles_on_auth_user_created'
      and tgrelid = 'auth.users'::regclass
      and not tgisinternal
  ) then
    execute 'create trigger profiles_on_auth_user_created after insert on auth.users for each row execute function public.uhms_handle_new_auth_user()';
  end if;
end;
$$;

-- Backfill profiles for Auth users that existed before this migration.
-- Existing profiles are not overwritten except for their Auth email mirror.
insert into public.profiles (id, full_name, email)
select id, coalesce(raw_user_meta_data ->> 'full_name', ''), email
from auth.users
on conflict (id) do update set email = excluded.email;
