import { useState } from 'react'
import { Outlet } from 'react-router-dom'
import { Sidebar } from './Sidebar'
import { Header } from './Header'

export function DashboardLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  return <div className="min-h-screen bg-background/90"><div className="flex min-h-screen"><Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} /><div className="flex min-w-0 flex-1 flex-col"><Header onMenuClick={() => setSidebarOpen(true)} /><main className="app-main flex-1 overflow-x-hidden"><div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8"><Outlet /></div></main><footer className="border-t border-border/60 bg-card/40 px-6 py-4 text-center text-[11px] text-muted-foreground">نظام إدارة القاعات الجامعية <span className="mx-1 text-primary">•</span> بيانات متصلة مباشرة بـ Supabase</footer></div></div></div>
}
