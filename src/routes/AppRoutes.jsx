import { Navigate, Route, Routes } from 'react-router-dom'
import { DashboardLayout } from '../components/layout/DashboardLayout'
import { useAuth } from '../context/AuthContext'
import { can } from '../lib/permissions'
import { Login } from '../pages/auth/Login'
import { Dashboard } from '../pages/dashboard/Dashboard'
import { Buildings } from '../pages/buildings/Buildings'
import { Halls } from '../pages/halls/Halls'
import { Reservations } from '../pages/reservations/Reservations'
import { Departments } from '../pages/departments/Departments'
import { DepartmentLevels } from '../pages/departmentLevels/DepartmentLevels'
import { Levels } from '../pages/levels/Levels'
import { Batches } from '../pages/batches/Batches'
import { Subjects } from '../pages/subjects/Subjects'
import { Instructors } from '../pages/instructors/Instructors'
import { Lectures } from '../pages/lectures/Lectures'
import { Schedule } from '../pages/schedule/Schedule'
import { ConflictCenter } from '../pages/conflicts/ConflictCenter'
import { Users } from '../pages/users/Users'
import { Roles } from '../pages/roles/Roles'
import { Reports } from '../pages/reports/Reports'
import { Settings } from '../pages/settings/Settings'
import { PermissionGuard, ProtectedRoute } from './ProtectedRoute'

function Guarded({ permission, children }) {
  const { profile } = useAuth()
  return can(profile, permission) ? children : <Navigate to="/dashboard" replace />
}

export function AppRoutes() {
  return <Routes><Route path="/login" element={<Login />} /><Route element={<ProtectedRoute />}><Route element={<DashboardLayout />}><Route index element={<Navigate to="/dashboard" replace />} /><Route path="dashboard" element={<Guarded permission="dashboard.view"><Dashboard /></Guarded>} /><Route path="buildings" element={<Guarded permission="buildings.view"><Buildings /></Guarded>} /><Route path="halls" element={<Guarded permission="halls.view"><Halls /></Guarded>} /><Route path="reservations" element={<Guarded permission="hall_reservations.view"><Reservations /></Guarded>} /><Route path="departments" element={<Guarded permission="departments.view"><Departments /></Guarded>} /><Route path="department-levels" element={<Guarded permission="departments.update"><DepartmentLevels /></Guarded>} /><Route path="levels" element={<Guarded permission="levels.view"><Levels /></Guarded>} /><Route path="batches" element={<Guarded permission="batches.view"><Batches /></Guarded>} /><Route path="subjects" element={<Guarded permission="subjects.view"><Subjects /></Guarded>} /><Route path="instructors" element={<Guarded permission="instructors.view"><Instructors /></Guarded>} /><Route path="lectures" element={<Guarded permission="lectures.view"><Lectures /></Guarded>} /><Route path="schedule" element={<Guarded permission="lectures.view"><Schedule /></Guarded>} /><Route path="conflicts" element={<Guarded permission="lectures.view"><ConflictCenter /></Guarded>} /><Route path="users" element={<Guarded permission="users.view"><Users /></Guarded>} /><Route path="roles" element={<Guarded permission="roles.view"><Roles /></Guarded>} /><Route path="reports" element={<Guarded permission="reports.view"><Reports /></Guarded>} /><Route path="settings" element={<Guarded permission="settings.view"><Settings /></Guarded>} /></Route></Route><Route path="*" element={<Navigate to="/dashboard" replace />} /></Routes>
}
