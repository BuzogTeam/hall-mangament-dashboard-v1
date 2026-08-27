import { useEffect } from 'react'

export function usePageTitle(title) {
  useEffect(() => { document.title = title ? `${title} | إدارة القاعات الجامعية` : 'إدارة القاعات الجامعية' }, [title])
}
