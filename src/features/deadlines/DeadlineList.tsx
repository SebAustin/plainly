import { daysUntil } from '../../core/decode'
import type { TrackedDeadline } from '../../letters/deadlineStore'
import './deadlines.css'

interface DeadlineListProps {
  deadlines: readonly TrackedDeadline[]
  onRemove: (id: string) => void
}

function describe(days: number): string {
  if (days < 0) return `${-days}d overdue`
  if (days === 0) return 'today'
  return `${days}d`
}

export function DeadlineList({ deadlines, onRemove }: DeadlineListProps) {
  if (deadlines.length === 0) return null
  return (
    <section className="deadlines" aria-labelledby="deadlines-heading">
      <h2 id="deadlines-heading">Coming up</h2>
      <ul>
        {deadlines.map((deadline) => {
          const days = daysUntil(deadline.deadline)
          return (
            <li key={deadline.id} className={days <= 7 ? 'is-soon' : undefined}>
              <strong>{describe(days)}</strong>
              <span>
                {deadline.sender}
                <small>{deadline.category}</small>
              </span>
              <button
                type="button"
                className="link-button"
                onClick={() => onRemove(deadline.id)}
                aria-label={`Stop tracking ${deadline.sender}`}
              >
                Done
              </button>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
