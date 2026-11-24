import { useState, type FormEvent } from 'react'
import type { ConversationTurn, Draft } from '../../app/usePlainly'
import { SourceStamp } from '../decode/SourceStamp'
import './followup.css'

interface FollowUpProps {
  conversation: readonly ConversationTurn[]
  draft: Draft | null
  isAsking: boolean
  isDrafting: boolean
  isOnline: boolean
  /** False when only pattern rules can hide details, so names and addresses would be sent. */
  namesHidden: boolean
  onAsk: (question: string) => void
  onDraft: (goal: string) => void
}

const SUGGESTED_QUESTIONS = [
  'What happens if I miss the deadline?',
  'Who do I call, and what do I say?',
  'Can I ask for more time?',
]

const DEFAULT_REPLY_GOAL = 'Ask for more time and what my options are'

export function FollowUp({
  conversation,
  draft,
  isAsking,
  isDrafting,
  isOnline,
  namesHidden,
  onAsk,
  onDraft,
}: FollowUpProps) {
  const [question, setQuestion] = useState('')
  const [goal, setGoal] = useState(DEFAULT_REPLY_GOAL)

  function submitQuestion(event: FormEvent) {
    event.preventDefault()
    const trimmed = question.trim()
    if (!trimmed) return
    onAsk(trimmed)
    setQuestion('')
  }

  return (
    <section className="followup" aria-labelledby="followup-heading">
      <h3 id="followup-heading">Ask about this letter</h3>
      <p className="followup-note">
        {namesHidden
          ? 'Questions go to the cloud model. Names, addresses and account numbers are hidden first, then put back in the answer on this device.'
          : 'Questions go to the cloud model. Only email addresses and phone, ID and account numbers can be hidden: names and addresses cannot.'}
      </p>

      {conversation.length > 0 && (
        <ol className="conversation" aria-live="polite">
          {conversation.map((turn, index) => (
            <li key={index} className={`turn turn-${turn.role}`}>
              <span className="turn-who">{turn.role === 'you' ? 'You' : 'Plainly'}</span>
              <p>{turn.text}</p>
            </li>
          ))}
          {isAsking && <li className="turn turn-plainly turn-pending">Thinking…</li>}
        </ol>
      )}

      {conversation.length === 0 && (
        <ul className="suggestions">
          {SUGGESTED_QUESTIONS.map((suggestion) => (
            <li key={suggestion}>
              <button type="button" disabled={!isOnline || isAsking} onClick={() => onAsk(suggestion)}>
                {suggestion}
              </button>
            </li>
          ))}
        </ul>
      )}

      <form className="ask-form" onSubmit={submitQuestion}>
        <label className="visually-hidden" htmlFor="question">
          Your question
        </label>
        <input
          id="question"
          value={question}
          onChange={(event) => setQuestion(event.target.value)}
          placeholder={isOnline ? 'Ask anything about this letter' : 'Questions need a connection'}
          disabled={!isOnline}
        />
        <button type="submit" className="button-primary" disabled={!isOnline || isAsking || !question.trim()}>
          Ask
        </button>
      </form>

      <form
        className="draft-form"
        onSubmit={(event) => {
          event.preventDefault()
          if (goal.trim()) onDraft(goal.trim())
        }}
      >
        <h3>Write back</h3>
        <label htmlFor="reply-goal">What should the reply ask for?</label>
        <div className="ask-form">
          <input id="reply-goal" value={goal} onChange={(event) => setGoal(event.target.value)} />
          <button type="submit" className="button-quiet" disabled={isDrafting || !goal.trim()}>
            {isDrafting ? 'Writing…' : 'Draft a reply'}
          </button>
        </div>
      </form>

      {draft && (
        <div className="draft">
          <div className="receipt-line">
            <span className="eyebrow">Your draft</span>
            <SourceStamp source={draft.source} />
          </div>
          <pre>{draft.text}</pre>
          <button
            type="button"
            className="link-button"
            onClick={() => void navigator.clipboard.writeText(draft.text)}
          >
            Copy
          </button>
        </div>
      )}
    </section>
  )
}
