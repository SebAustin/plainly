import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  type Firestore,
} from 'firebase/firestore'
import { nextDeadline, type Decode, type LetterCategory, type Urgency } from '../core/decode'

/**
 * A tracked deadline is the only part of a letter that is synced. It holds the
 * sending organisation, the category, the date and the amount. The summary,
 * the letter and every personal detail stay on the device.
 */
export interface TrackedDeadline {
  id: string
  sender: string
  category: LetterCategory
  urgency: Urgency
  deadline: string
  amountDue: Decode['amountDue']
}

export interface DeadlineStore {
  subscribe(onChange: (deadlines: TrackedDeadline[]) => void, onError: (error: Error) => void): () => void
  track(decode: Decode): Promise<void>
  remove(id: string): Promise<void>
}

export function createDeadlineStore(db: Firestore, userId: string): DeadlineStore {
  const deadlines = collection(db, 'users', userId, 'deadlines')

  return {
    subscribe(onChange, onError) {
      return onSnapshot(
        query(deadlines, orderBy('deadline')),
        (snapshot) =>
          onChange(
            snapshot.docs.map((entry) => ({ ...(entry.data() as Omit<TrackedDeadline, 'id'>), id: entry.id })),
          ),
        onError,
      )
    },

    async track(decode) {
      const deadline = nextDeadline(decode)
      if (!deadline) throw new Error('This letter has no deadline to track.')
      await addDoc(deadlines, {
        sender: decode.sender,
        category: decode.category,
        urgency: decode.urgency,
        deadline,
        amountDue: decode.amountDue,
        createdAt: serverTimestamp(),
      })
    },

    async remove(id) {
      await deleteDoc(doc(deadlines, id))
    },
  }
}
