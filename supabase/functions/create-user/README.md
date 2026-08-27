# create-user Edge Function

هذه الدالة تنفذ دعوة المستخدم عبر `auth.admin.inviteUserByEmail` ثم تنشئ Profile. المفتاح الوحيد الحساس هو `SUPABASE_SERVICE_ROLE_KEY` ويُحفظ داخل Secrets في Supabase Edge Functions فقط.

```bash
supabase functions deploy create-user
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_URL=... SUPABASE_ANON_KEY=...
```

الواجهة تستدعي الدالة عبر `supabase.functions.invoke('create-user')` ولا تحتوي على أي مفتاح Service Role.
