import { selectRows } from './baseService'

export const notificationsService = {
  async list() {
    const [lectures, halls] = await Promise.all([
      selectRows('lectures', 'id,created_at,updated_at,subject:subjects!lectures_subject_id_fkey(title)', (query) => query.order('updated_at', { ascending: false }).limit(5)),
      selectRows('halls', 'id,created_at,title', (query) => query.order('created_at', { ascending: false }).limit(5)),
    ])
    return [
      ...(lectures || []).map((item) => ({ id: `lecture-${item.id}`, type: 'lecture', title: `تم تحديث محاضرة ${item.subject?.title || ''}`, date: item.updated_at || item.created_at })),
      ...(halls || []).map((item) => ({ id: `hall-${item.id}`, type: 'hall', title: `تمت إضافة القاعة ${item.title || ''}`, date: item.created_at })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date)).slice(0, 5)
  },
}
