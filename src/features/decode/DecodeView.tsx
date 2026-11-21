import { daysUntil, nextDeadline, type Decode } from '../../core/decode'
import type { DecodedLetter } from '../../letters/letterService'
import { SourceStamp } from './SourceStamp'
import './decode.css'

interface DecodeViewProps {
  letter: DecodedLetter
  canTrackDeadline: boolean
  isTracked: boolean
  isTracking: boolean
  onTrackDeadline: () => void
}

const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'full' })

function formatDate(isoDate: string): string {
  const [year, month, day] = isoDate.split('-').map(Number)
  return longDate.format(new Date(year, month - 1, day))
}

function formatAmount(amount: NonNullable<Decode['amountDue']>): string {
  try {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: amount.currency }).format(
      amount.value,
    )
  } catch {
    // The model returned a currency code Intl does not know.
    return `${amount.value} ${amount.currency}`
  }
}

function describeDays(days: number): { figure: string; label: string } {
  if (days < 0) return { figure: String(-days), label: days === -1 ? 'day overdue' : 'days overdue' }
  if (days === 0) return { figure: 'Today', label: 'is the deadline' }
  return { figure: String(days), label: days === 1 ? 'day left' : 'days left' }
}

export function DecodeView({
  letter,
  canTrackDeadline,
  isTracked,
  isTracking,
  onTrackDeadline,
}: DecodeViewProps) {
  const { decode } = letter
  const deadline = nextDeadline(decode)
  const days = deadline ? describeDays(daysUntil(deadline)) : null

  return (
    <article className="decode" aria-labelledby="decode-heading">
      <header className="decode-header">
        <div>
          <p className="eyebrow">
            {decode.category} · {decode.urgency} urgency
          </p>
          <h2 id="decode-heading">{decode.sender}</h2>
        </div>
        <SourceStamp
          source={letter.source}
          isRedacted={letter.cloudContext !== null && letter.cloudContext.level !== 'none'}
          size="large"
        />
      </header>

      <p className="decode-summary">{decode.summary}</p>

      {(days || decode.amountDue) && (
        <dl className={`decode-figures urgency-${decode.urgency}`}>
          {days && deadline && (
            <div>
              <dt>{days.label}</dt>
              <dd>{days.figure}</dd>
              <p>{formatDate(deadline)}</p>
            </div>
          )}
          {decode.amountDue && (
            <div>
              <dt>you owe</dt>
              <dd>{formatAmount(decode.amountDue)}</dd>
            </div>
          )}
        </dl>
      )}

      <section aria-labelledby="actions-heading">
        <h3 id="actions-heading">What you need to do</h3>
        {decode.actions.length === 0 ? (
          <p>Nothing. Keep this letter for your records.</p>
        ) : (
          <ol className="decode-actions">
            {decode.actions.map((action) => (
              <li key={action.what}>
                <label>
                  <input type="checkbox" />
                  <span>
                    {action.what}
                    {action.deadline && <em> By {formatDate(action.deadline)}.</em>}
                  </span>
                </label>
              </li>
            ))}
          </ol>
        )}
        {canTrackDeadline && (
          <p className="decode-track">
            <button
              type="button"
              className="button-quiet"
              onClick={onTrackDeadline}
              disabled={isTracked || isTracking}
            >
              {isTracked ? 'Deadline tracked' : isTracking ? 'Saving…' : 'Track this deadline'}
            </button>
            <small>Saves only the sender, date and amount. The letter stays here.</small>
          </p>
        )}
      </section>

      {decode.glossary.length > 0 && (
        <section aria-labelledby="glossary-heading">
          <h3 id="glossary-heading">Words they used</h3>
          <dl className="decode-glossary">
            {decode.glossary.map((entry) => (
              <div key={entry.term}>
                <dt>{entry.term}</dt>
                <dd>{entry.plain}</dd>
              </div>
            ))}
          </dl>
        </section>
      )}
    </article>
  )
}
