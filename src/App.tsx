import { useEffect, useRef } from 'react'
import { usePlainly } from './app/usePlainly'
import { Composer } from './features/composer/Composer'
import { DeadlineList } from './features/deadlines/DeadlineList'
import { DecodeView } from './features/decode/DecodeView'
import { FollowUp } from './features/followup/FollowUp'
import { Receipt } from './features/receipt/Receipt'
import { StatusBar } from './features/status/StatusBar'
import { missingConfigKeys } from './firebase/config'

const PROMISES = [
  {
    title: 'Read on your device',
    body: 'Gemini Nano, built into Chrome, reads the letter. The letter itself is not uploaded.',
  },
  {
    title: 'Hidden before the cloud',
    body: 'Questions need a bigger model. Your name, address and account numbers are blacked out first.',
  },
  {
    title: 'A receipt for every call',
    body: 'See which model answered, and the exact text the cloud received.',
  },
]

function SetupNotice() {
  return (
    <section className="notice" role="status">
      <h2>Finish setup to read letters</h2>
      <p>
        Plainly runs on Firebase AI Logic and no Firebase project is configured yet. Run{' '}
        <code>bash scripts/setup-firebase.sh</code>, or copy <code>.env.example</code> to{' '}
        <code>.env.local</code> and fill in:
      </p>
      <ul>
        {missingConfigKeys.map((key) => (
          <li key={key}>
            <code>{key}</code>
          </li>
        ))}
      </ul>
    </section>
  )
}

export default function App() {
  const plainly = usePlainly()
  const consentButton = useRef<HTMLButtonElement>(null)

  // A consent question can appear far from where the reader clicked (asking a
  // question lower on the page), so bring it into view and give it focus.
  useEffect(() => {
    const button = consentButton.current
    if (!plainly.pendingConsent || !button) return
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    button.scrollIntoView({ block: 'center', behavior: reduceMotion ? 'auto' : 'smooth' })
    button.focus({ preventScroll: true })
  }, [plainly.pendingConsent])
  const { letter } = plainly

  return (
    <>
      <header className="masthead">
        <div>
          <h1>Plainly</h1>
          <p>Official mail, in plain words. Read privately on your device.</p>
        </div>
        {plainly.runtimeKind !== 'unconfigured' && (
          <StatusBar
            deviceModel={plainly.deviceModel}
            downloadProgress={plainly.downloadProgress}
            isOnline={plainly.isOnline}
            onDownload={() => void plainly.downloadDeviceModel()}
          />
        )}
      </header>

      {plainly.runtimeKind === 'fixture' && (
        <p className="banner" role="status">
          Fixture mode: answers below are canned test data, not from a model.
        </p>
      )}

      <main className="desk">
        <div className="desk-left">
          <Composer
            isReading={plainly.busy === 'reading'}
            isDisabled={plainly.runtimeKind === 'unconfigured'}
            onRead={(input) => void plainly.read(input)}
          />
          <DeadlineList
            deadlines={plainly.deadlines}
            onRemove={(id) => void plainly.removeDeadline(id)}
          />
        </div>

        <div className="desk-right" aria-live="polite">
          {plainly.runtimeKind === 'unconfigured' && <SetupNotice />}

          {plainly.error && (
            <p className="notice notice-error" role="alert">
              {plainly.error}
            </p>
          )}

          {plainly.pendingConsent?.reason === 'file' && (
            <section className="notice" role="alertdialog" aria-labelledby="consent-heading">
              <h2 id="consent-heading">This file can't be read on this device</h2>
              <p>
                To explain it, Plainly would send the file to Google's Gemini in the cloud exactly as it is.
                Personal details in a photo or PDF can't be hidden first. Pasting the text instead keeps
                them private.
              </p>
              <div className="composer-actions">
                <button
                  ref={consentButton}
                  type="button"
                  className="button-primary"
                  onClick={plainly.acceptConsent}
                >
                  Send this file to the cloud
                </button>
                <button type="button" className="button-quiet" onClick={plainly.dismissConsent}>
                  Keep it here
                </button>
              </div>
            </section>
          )}

          {plainly.pendingConsent?.reason === 'names' && (
            <section className="notice" role="alertdialog" aria-labelledby="consent-heading">
              <h2 id="consent-heading">Names and addresses couldn't be hidden</h2>
              <p>
                The on-device model's list of names couldn't be read, so Plainly can only hide email
                addresses and phone, ID and account numbers. If you continue, your name and address will
                be sent to Google's Gemini in the cloud.
              </p>
              <div className="composer-actions">
                <button
                  ref={consentButton}
                  type="button"
                  className="button-primary"
                  onClick={plainly.acceptConsent}
                >
                  Send to the cloud
                </button>
                <button type="button" className="button-quiet" onClick={plainly.dismissConsent}>
                  Keep it here
                </button>
              </div>
            </section>
          )}

          {plainly.busy === 'reading' && <p className="reading">Reading your letter…</p>}

          {letter ? (
            <>
              <DecodeView
                letter={letter}
                canTrackDeadline={plainly.canTrackDeadline}
                isTracked={plainly.isTracked}
                isTracking={plainly.busy === 'tracking'}
                onTrackDeadline={() => void plainly.trackDeadline()}
              />
              <FollowUp
                conversation={plainly.conversation}
                draft={plainly.draft}
                isAsking={plainly.busy === 'asking'}
                isDrafting={plainly.busy === 'drafting'}
                isOnline={plainly.isOnline}
                namesHidden={
                  plainly.context
                    ? plainly.context.level === 'device-assisted'
                    : plainly.deviceModel !== 'unavailable'
                }
                onAsk={(question) => void plainly.ask(question)}
                onDraft={(goal) => void plainly.writeDraft(goal)}
              />
              <Receipt entries={plainly.receipt} />
            </>
          ) : (
            plainly.busy !== 'reading' && (
              <ol className="promises">
                {PROMISES.map((promise, index) => (
                  <li key={promise.title}>
                    <span aria-hidden="true">{index + 1}</span>
                    <h2>{promise.title}</h2>
                    <p>{promise.body}</p>
                  </li>
                ))}
              </ol>
            )
          )}
        </div>
      </main>

      <footer className="colophon">
        Plainly explains letters. It is not legal, medical or financial advice. Built with Firebase AI Logic
        hybrid inference.
      </footer>
    </>
  )
}
