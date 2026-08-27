import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import * as authService from '../services/authService'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [user, setUser] = useState(null)
  const [profile, setProfile] = useState(null)
  const [setupRequired, setSetupRequired] = useState(false)
  const [loading, setLoading] = useState(true)
  const [profileLoading, setProfileLoading] = useState(false)
  const profileRequestRef = useRef(0)

  const loadProfile = useCallback(async (nextUser) => {
    const requestId = ++profileRequestRef.current
    if (!nextUser) {
      setProfile(null)
      setSetupRequired(false)
      setProfileLoading(false)
      return
    }
    setProfileLoading(true)
    try {
      const result = await authService.getProfile(nextUser.id)
      if (requestId !== profileRequestRef.current) return
      setProfile(result.profile)
      setSetupRequired(result.setupRequired)
    } catch (error) {
      if (requestId !== profileRequestRef.current) return
      console.error('Unable to load profile', error)
      setProfile(null)
      setSetupRequired(false)
    } finally {
      if (requestId === profileRequestRef.current) setProfileLoading(false)
    }
  }, [])

  const refreshProfile = useCallback(async () => {
    if (user) await loadProfile(user)
  }, [loadProfile, user])

  useEffect(() => {
    let mounted = true
    authService.getSession().then(async (currentSession) => {
      if (!mounted) return
      setSession(currentSession)
      setUser(currentSession?.user || null)
      await loadProfile(currentSession?.user || null)
    }).catch((error) => console.error('Unable to restore Supabase session', error)).finally(() => { if (mounted) setLoading(false) })

    const { data } = authService.onAuthStateChange((_event, nextSession) => {
      if (!mounted) return
      setSession(nextSession)
      setUser(nextSession?.user || null)
      // Avoid awaiting Supabase work inside the auth callback.
      Promise.resolve().then(() => loadProfile(nextSession?.user || null))
    })
    return () => { mounted = false; data?.subscription?.unsubscribe() }
  }, [loadProfile])

  const value = useMemo(() => ({ session, user, profile, loading, profileLoading, setupRequired, refreshProfile }), [session, user, profile, loading, profileLoading, setupRequired, refreshProfile])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
