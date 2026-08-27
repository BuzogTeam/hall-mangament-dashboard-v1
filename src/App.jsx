import { BrowserRouter } from 'react-router-dom'
import { QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'sonner'
import { AuthProvider } from './context/AuthContext'
import { ThemeProvider } from './context/ThemeContext'
import { queryClient } from './lib/queryClient'
import { AppRoutes } from './routes/AppRoutes'

export default function App() {
  return <QueryClientProvider client={queryClient}><ThemeProvider><AuthProvider><BrowserRouter><AppRoutes /></BrowserRouter><Toaster position="top-left" richColors closeButton /></AuthProvider></ThemeProvider></QueryClientProvider>
}
