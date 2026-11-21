import type { ReceiptEntry } from '../../inference/receipt'
import { SourceStamp } from '../decode/SourceStamp'
import { RedactedText } from './RedactedText'
import './receipt.css'

/** The privacy receipt: every model call for this letter, and what each one saw. */
export function Receipt({ entries }: { entries: readonly ReceiptEntry[] }) {
  if (entries.length === 0) return null
  const cloudCalls = entries.filter((entry) => entry.source === 'in_cloud').length

  return (
    <section className="receipt" aria-labelledby="receipt-heading">
      <h3 id="receipt-heading">Privacy receipt</h3>
      <p className="receipt-total">
        {entries.length} model {entries.length === 1 ? 'call' : 'calls'} · {cloudCalls} left this device
      </p>
      <ol>
        {entries.map((entry) => (
          <li key={entry.id}>
            <div className="receipt-line">
              <span>{entry.task}</span>
              <SourceStamp source={entry.source} />
            </div>
            {entry.sentToCloud !== null && (
              <details>
                <summary>See exactly what the cloud received</summary>
                {entry.sentFile && <p className="receipt-note">Your file was sent as-is, with your consent.</p>}
                <pre>
                  <RedactedText text={entry.sentToCloud} />
                </pre>
              </details>
            )}
          </li>
        ))}
      </ol>
    </section>
  )
}
