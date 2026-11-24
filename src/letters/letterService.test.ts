import { describe, expect, test } from 'vitest'
import type { Environment } from '../core/routing'
import type {
  ChatRequest,
  GenerateRequest,
  Inference,
  InferenceResult,
} from '../inference/inference'
import {
  askFollowUp,
  decodeLetter,
  draftReply,
  NeedsCloudConsentError,
  prepareCloudContext,
} from './letterService'
import { DECODE_JSON_SCHEMA } from '../core/decode'

const LETTER =
  'Dear Maria Okafor, your balance of $1,284.50 is due 2026-12-14. Questions: billing@northgate.org.'

const decodeAnswer = (who: string) =>
  JSON.stringify({
    sender: 'Northgate Health',
    category: 'medical',
    summary: `${who} owes money for a clinic visit.`,
    urgency: 'high',
    actions: [{ what: `Pay the balance, ${who}`, deadline: '2026-12-14' }],
    amountDue: { value: 1284.5, currency: 'USD' },
    glossary: [],
  })

const entitiesAnswer = JSON.stringify({ entities: [{ type: 'NAME', value: 'Maria Okafor' }] })

const environment: Environment = {
  deviceModel: 'available',
  isOnline: true,
  hasCloudConsent: false,
  deviceTokenBudget: 6000,
}

/** A fake model that records everything it was sent. */
function fakeInference(answer: (request: GenerateRequest) => string, chatAnswer = '') {
  const generated: GenerateRequest[] = []
  const chats: ChatRequest[] = []
  const inference: Inference = {
    async generate(request): Promise<InferenceResult> {
      generated.push(request)
      return {
        text: answer(request),
        source: request.mode === 'only_in_cloud' ? 'in_cloud' : 'on_device',
      }
    },
    async chat(request): Promise<InferenceResult> {
      chats.push(request)
      return { text: chatAnswer, source: 'in_cloud' }
    },
    deviceModelStatus: async () => 'available',
    downloadDeviceModel: async () => {},
  }
  const sentToCloud = () =>
    [
      ...generated.filter((request) => request.mode !== 'only_on_device'),
      ...chats,
    ]
      .map((request) => JSON.stringify(request))
      .join('\n')
  return { inference, generated, chats, sentToCloud }
}

const answerBySchema = (request: GenerateRequest): string =>
  request.jsonSchema === DECODE_JSON_SCHEMA
    ? decodeAnswer(request.mode === 'only_in_cloud' ? '[NAME_1]' : 'Maria Okafor')
    : entitiesAnswer

describe('decodeLetter', () => {
  test('a short letter is decoded with a single on-device call and nothing reaches the cloud', async () => {
    const model = fakeInference(answerBySchema)

    const result = await decodeLetter({ kind: 'text', text: LETTER }, environment, model.inference)

    expect(result).toMatchObject({
      ok: true,
      letter: { source: 'on_device', decode: { sender: 'Northgate Health' } },
    })
    expect(model.generated.map((request) => request.mode)).toEqual(['only_on_device'])
    expect(model.sentToCloud()).toBe('')
  })

  test('a long letter reaches the cloud without the name or email, and comes back with them restored', async () => {
    const model = fakeInference(answerBySchema)
    const tightBudget = { ...environment, deviceTokenBudget: 10 }

    const result = await decodeLetter({ kind: 'text', text: LETTER }, tightBudget, model.inference)

    expect(model.sentToCloud()).not.toContain('Maria Okafor')
    expect(model.sentToCloud()).not.toContain('billing@northgate.org')
    expect(model.sentToCloud()).toContain('[NAME_1]')
    expect(result).toMatchObject({
      ok: true,
      letter: {
        source: 'in_cloud',
        decode: {
          summary: 'Maria Okafor owes money for a clinic visit.',
          actions: [{ what: 'Pay the balance, Maria Okafor' }],
        },
      },
    })
  })

  test('a PDF without consent is blocked before any model is called', async () => {
    const model = fakeInference(answerBySchema)

    const result = await decodeLetter(
      { kind: 'pdf', attachment: { base64: 'JVBERi0=', mimeType: 'application/pdf' } },
      environment,
      model.inference,
    )

    expect(result).toEqual({ ok: false, reason: 'needs-cloud-consent' })
    expect(model.generated).toEqual([])
  })

  test('an unreadable model answer is retried once, then reported instead of shown', async () => {
    const model = fakeInference(() => 'I cannot help with that.')

    const result = await decodeLetter({ kind: 'text', text: LETTER }, environment, model.inference)

    expect(result).toEqual({ ok: false, reason: 'unreadable-answer' })
    expect(model.generated).toHaveLength(2)
  })
})

describe('askFollowUp', () => {
  test('the question and the letter reach the cloud redacted, and the answer is restored on device', async () => {
    const model = fakeInference(answerBySchema, 'Yes [NAME_1], email [EMAIL_1] to ask for a plan.')
    const context = await prepareCloudContext(
      { kind: 'text', text: LETTER },
      environment,
      model.inference,
    )

    const reply = await askFollowUp(
      context,
      [],
      'Can Maria Okafor get a payment plan?',
      model.inference,
    )

    expect(model.sentToCloud()).not.toContain('Maria Okafor')
    expect(model.sentToCloud()).not.toContain('billing@northgate.org')
    expect(model.chats[0].message).toBe('Can [NAME_1] get a payment plan?')
    expect(reply.answer).toBe('Yes Maria Okafor, email billing@northgate.org to ask for a plan.')
  })
})

describe('prepareCloudContext', () => {
  test('without a device model, only pattern rules redact and the context says so', async () => {
    const model = fakeInference(answerBySchema)

    const context = await prepareCloudContext(
      { kind: 'text', text: LETTER },
      { ...environment, deviceModel: 'unavailable' },
      model.inference,
    )

    expect(context.level).toBe('rules-only')
    expect(context.redactedText).toContain('[EMAIL_1]')
    expect(context.redactedText).toContain('Maria Okafor')
    expect(model.generated).toEqual([])
  })
})

const UNREADABLE_DETAILS = 'Here are the names: Maria Okafor'

const answerWithUnreadableDetails = (request: GenerateRequest): string =>
  request.jsonSchema === DECODE_JSON_SCHEMA
    ? decodeAnswer(request.mode === 'only_in_cloud' ? '[NAME_1]' : 'Maria Okafor')
    : UNREADABLE_DETAILS

const findCalls = (requests: GenerateRequest[]) =>
  requests.filter((request) => request.task === 'Find personal details').length

describe('when the on-device list of names cannot be read', () => {
  test('it is retried once, then the context is marked pattern-rules only', async () => {
    const model = fakeInference(answerWithUnreadableDetails)

    const context = await prepareCloudContext({ kind: 'text', text: LETTER }, environment, model.inference)

    expect(findCalls(model.generated)).toBe(2)
    expect(context).toMatchObject({ level: 'rules-only', unreadableNames: true })
  })

  test('an empty list is a valid answer and keeps device-assisted redaction', async () => {
    const model = fakeInference((request) =>
      request.jsonSchema === DECODE_JSON_SCHEMA ? decodeAnswer('x') : '{"entities":[]}',
    )

    const context = await prepareCloudContext({ kind: 'text', text: LETTER }, environment, model.inference)

    expect(findCalls(model.generated)).toBe(1)
    expect(context).toMatchObject({ level: 'device-assisted', unreadableNames: false })
  })

  test('a long letter is not sent to the cloud until the reader agrees', async () => {
    const model = fakeInference(answerWithUnreadableDetails)
    const tightBudget = { ...environment, deviceTokenBudget: 10 }

    const result = await decodeLetter({ kind: 'text', text: LETTER }, tightBudget, model.inference)

    expect(result).toEqual({ ok: false, reason: 'needs-cloud-consent' })
    expect(model.sentToCloud()).toBe('')
  })

  test('with consent the long letter is sent, marked pattern-rules only', async () => {
    const model = fakeInference(answerWithUnreadableDetails)
    const agreed = { ...environment, deviceTokenBudget: 10, hasCloudConsent: true }

    const result = await decodeLetter({ kind: 'text', text: LETTER }, agreed, model.inference)

    expect(result).toMatchObject({ ok: true, letter: { cloudContext: { level: 'rules-only' } } })
    expect(model.sentToCloud()).not.toContain('billing@northgate.org')
  })

  test('a question is not sent until the reader agrees', async () => {
    const model = fakeInference(answerWithUnreadableDetails, 'ok')
    const context = await prepareCloudContext({ kind: 'text', text: LETTER }, environment, model.inference)

    await expect(askFollowUp(context, [], 'Why?', model.inference)).rejects.toBeInstanceOf(
      NeedsCloudConsentError,
    )
    expect(model.chats).toEqual([])

    await askFollowUp(context, [], 'Why?', model.inference, true)
    expect(model.chats).toHaveLength(1)
  })

  test('a reply is not drafted until the reader agrees', async () => {
    const model = fakeInference(answerWithUnreadableDetails)
    const context = await prepareCloudContext({ kind: 'text', text: LETTER }, environment, model.inference)

    const result = await draftReply(context, 'More time', environment, model.inference)

    expect(result).toEqual({ blocked: 'needs-cloud-consent' })
    expect(model.generated.filter((request) => request.task === 'Draft a reply')).toEqual([])
  })
})
