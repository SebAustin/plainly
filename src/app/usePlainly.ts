import { useCallback, useEffect, useMemo, useState } from 'react'
import { nextDeadline } from '../core/decode'
import type { BlockReason, DeviceModelStatus, Environment } from '../core/routing'
import { REMOTE_CONFIG_DEFAULTS } from '../firebase/config'
import type { ChatTurn, InferenceSource } from '../inference/inference'
import { withReceipt, type ReceiptEntry } from '../inference/receipt'
import type { TrackedDeadline } from '../letters/deadlineStore'
import {
  askFollowUp,
  decodeLetter,
  draftReply,
  NeedsCloudConsentError,
  prepareCloudContext,
  type CloudContext,
  type DecodedLetter,
  type LetterInput,
} from '../letters/letterService'
import { createRuntime } from './runtime'
import { useOnlineStatus } from './useOnlineStatus'

export interface ConversationTurn {
  role: 'you' | 'plainly'
  text: string
}

export interface Draft {
  text: string
  source: InferenceSource
}

type Busy = 'reading' | 'asking' | 'drafting' | 'tracking' | null

/**
 * Something waiting for the reader's yes before it reaches the cloud:
 * a photo or PDF that cannot be redacted, or text whose names and addresses
 * the on-device model could not find.
 */
export interface ConsentRequest {
  reason: 'file' | 'names'
  action:
    | { kind: 'read'; input: LetterInput }
    | { kind: 'ask'; question: string }
    | { kind: 'draft'; goal: string }
}

const MESSAGES: Record<BlockReason | 'unreadable-answer' | 'failed', string> = {
  offline:
    'You are offline and this needs the cloud. Short letters and photos still work offline once the on-device model is installed.',
  'needs-cloud-consent': '',
  'unreadable-answer':
    'The model could not produce a clear reading of this letter. Try a sharper photo or paste the text.',
  failed: 'Something went wrong and the model did not answer. Nothing was saved. Please try again.',
}

function describeError(error: unknown): string {
  console.error(error)
  const detail = error instanceof Error ? ` (${error.message})` : ''
  return `${MESSAGES.failed}${detail}`
}

export function usePlainly() {
  const runtime = useMemo(() => createRuntime(), [])
  const isOnline = useOnlineStatus()

  const [receipt, setReceipt] = useState<ReceiptEntry[]>([])
  const [deviceModel, setDeviceModel] = useState<DeviceModelStatus>('unavailable')
  const [downloadProgress, setDownloadProgress] = useState<number | null>(null)
  const [deviceTokenBudget, setDeviceTokenBudget] = useState<number>(
    REMOTE_CONFIG_DEFAULTS.device_token_budget,
  )
  const [busy, setBusy] = useState<Busy>(null)
  const [error, setError] = useState<string | null>(null)
  const [pendingConsent, setPendingConsent] = useState<ConsentRequest | null>(null)
  /** The reader agreed to send this letter with names visible. Reset for each new letter. */
  const [namesConsent, setNamesConsent] = useState(false)
  const [input, setInput] = useState<LetterInput | null>(null)
  const [letter, setLetter] = useState<DecodedLetter | null>(null)
  const [context, setContext] = useState<CloudContext | null>(null)
  const [conversation, setConversation] = useState<ConversationTurn[]>([])
  const [cloudHistory, setCloudHistory] = useState<ChatTurn[]>([])
  const [draft, setDraft] = useState<Draft | null>(null)
  const [deadlines, setDeadlines] = useState<TrackedDeadline[]>([])
  const [isTracked, setIsTracked] = useState(false)

  const inference = useMemo(
    () =>
      runtime.kind === 'unconfigured'
        ? null
        : withReceipt(runtime.inference, (entry) => setReceipt((entries) => [...entries, entry])),
    [runtime],
  )

  useEffect(() => {
    if (runtime.kind === 'unconfigured') return
    let isCurrent = true
    runtime.inference.deviceModelStatus().then((status) => isCurrent && setDeviceModel(status))
    runtime.deviceTokenBudget.then((budget) => isCurrent && setDeviceTokenBudget(budget))
    return () => {
      isCurrent = false
    }
  }, [runtime])

  useEffect(() => {
    if (runtime.kind === 'unconfigured' || !runtime.deadlineStore) return
    let unsubscribe: (() => void) | undefined
    let isCurrent = true
    runtime.deadlineStore
      .then((store) => {
        if (!isCurrent) return
        unsubscribe = store.subscribe(setDeadlines, (storeError) =>
          setError(`Could not load your tracked deadlines (${storeError.message}).`),
        )
      })
      .catch((signInError: unknown) => setError(describeError(signInError)))
    return () => {
      isCurrent = false
      unsubscribe?.()
    }
  }, [runtime])

  const environment = useCallback(
    (hasCloudConsent: boolean): Environment => ({
      deviceModel,
      isOnline,
      hasCloudConsent,
      deviceTokenBudget,
    }),
    [deviceModel, isOnline, deviceTokenBudget],
  )

  const read = useCallback(
    async (nextInput: LetterInput, hasCloudConsent = false) => {
      if (!inference) return
      setBusy('reading')
      setError(null)
      setPendingConsent(null)
      setLetter(null)
      setContext(null)
      setConversation([])
      setCloudHistory([])
      setDraft(null)
      setIsTracked(false)
      setReceipt([])
      setInput(nextInput)
      setNamesConsent(hasCloudConsent)
      try {
        const result = await decodeLetter(nextInput, environment(hasCloudConsent), inference)
        if (result.ok) {
          setLetter(result.letter)
          setContext(result.letter.cloudContext)
        } else if (result.reason === 'needs-cloud-consent') {
          setPendingConsent({
            reason: nextInput.kind === 'text' ? 'names' : 'file',
            action: { kind: 'read', input: nextInput },
          })
        } else {
          setError(MESSAGES[result.reason])
        }
      } catch (readError) {
        setError(describeError(readError))
      } finally {
        setBusy(null)
      }
    },
    [inference, environment],
  )

  /** The redacted view of the letter, built once and reused by follow-up and drafting. */
  const ensureContext = useCallback(async (): Promise<CloudContext | null> => {
    if (context) return context
    if (!inference || !input || !letter) return null
    const prepared = await prepareCloudContext(input, environment(false), inference, letter.decode)
    setContext(prepared)
    return prepared
  }, [context, inference, input, letter, environment])

  const ask = useCallback(
    async (question: string, hasCloudConsent = false): Promise<void> => {
      if (!inference) return
      if (!isOnline) return setError(MESSAGES.offline)
      setBusy('asking')
      setError(null)
      setConversation((turns) => [...turns, { role: 'you', text: question }])
      try {
        const prepared = await ensureContext()
        if (!prepared) return
        const reply = await askFollowUp(
          prepared,
          cloudHistory,
          question,
          inference,
          hasCloudConsent || namesConsent,
        )
        setContext(reply.context)
        setCloudHistory((turns) => [...turns, ...reply.cloudTurns])
        setConversation((turns) => [...turns, { role: 'plainly', text: reply.answer }])
      } catch (askError) {
        // Take the unanswered question back out so the conversation stays truthful.
        setConversation((turns) => turns.slice(0, -1))
        if (askError instanceof NeedsCloudConsentError) {
          setPendingConsent({ reason: 'names', action: { kind: 'ask', question } })
        } else {
          setError(describeError(askError))
        }
      } finally {
        setBusy(null)
      }
    },
    [inference, isOnline, ensureContext, cloudHistory, namesConsent],
  )

  const writeDraft = useCallback(
    async (goal: string, hasCloudConsent = false): Promise<void> => {
      if (!inference) return
      setBusy('drafting')
      setError(null)
      try {
        const prepared = await ensureContext()
        if (!prepared) return
        const result = await draftReply(
          prepared,
          goal,
          environment(hasCloudConsent || namesConsent),
          inference,
        )
        if ('blocked' in result && result.blocked === 'needs-cloud-consent') {
          setPendingConsent({ reason: 'names', action: { kind: 'draft', goal } })
        } else if ('blocked' in result) {
          setError(MESSAGES[result.blocked])
        } else {
          setDraft(result)
        }
      } catch (draftError) {
        setError(describeError(draftError))
      } finally {
        setBusy(null)
      }
    },
    [inference, ensureContext, environment, namesConsent],
  )

  /** The reader said yes: remember it for this letter and run what was waiting. */
  const acceptConsent = useCallback(() => {
    if (!pendingConsent) return
    const { action } = pendingConsent
    setPendingConsent(null)
    setNamesConsent(true)
    if (action.kind === 'read') void read(action.input, true)
    else if (action.kind === 'ask') void ask(action.question, true)
    else void writeDraft(action.goal, true)
  }, [pendingConsent, read, ask, writeDraft])

  const downloadDeviceModel = useCallback(async () => {
    if (runtime.kind === 'unconfigured') return
    setDownloadProgress(0)
    setDeviceModel('downloading')
    try {
      await runtime.inference.downloadDeviceModel(setDownloadProgress)
    } catch (downloadError) {
      setError(describeError(downloadError))
    } finally {
      setDownloadProgress(null)
      setDeviceModel(await runtime.inference.deviceModelStatus())
    }
  }, [runtime])

  const trackDeadline = useCallback(async () => {
    if (runtime.kind === 'unconfigured' || !runtime.deadlineStore || !letter) return
    setBusy('tracking')
    try {
      await (await runtime.deadlineStore).track(letter.decode)
      setIsTracked(true)
    } catch (trackError) {
      setError(describeError(trackError))
    } finally {
      setBusy(null)
    }
  }, [runtime, letter])

  const removeDeadline = useCallback(
    async (id: string) => {
      if (runtime.kind === 'unconfigured' || !runtime.deadlineStore) return
      try {
        await (await runtime.deadlineStore).remove(id)
      } catch (removeError) {
        setError(describeError(removeError))
      }
    },
    [runtime],
  )

  return {
    runtimeKind: runtime.kind,
    isOnline,
    deviceModel,
    downloadProgress,
    busy,
    error,
    pendingConsent,
    letter,
    context,
    conversation,
    draft,
    receipt,
    deadlines,
    isTracked,
    canTrackDeadline:
      runtime.kind === 'firebase' && letter !== null && nextDeadline(letter.decode) !== null,
    read,
    ask,
    writeDraft,
    downloadDeviceModel,
    trackDeadline,
    removeDeadline,
    acceptConsent,
    dismissConsent: () => setPendingConsent(null),
  }
}

export type Plainly = ReturnType<typeof usePlainly>
