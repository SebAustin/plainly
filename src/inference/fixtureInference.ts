import { DECODE_JSON_SCHEMA } from '../core/decode'
import { PERSONAL_DETAILS_JSON_SCHEMA } from '../core/personalDetails'
import type { GenerateRequest, Inference, InferenceResult } from './inference'

/**
 * Development-only stand-in for the models, enabled with `?fixture` on a dev
 * server. It returns canned answers so the interface can be exercised without
 * a Firebase project or Gemini Nano. It is never included in production runs.
 */

const FIXTURE_DELAY_MS = 500

const CANNED_DECODE = {
  sender: 'Northgate Community Health',
  category: 'medical',
  summary:
    'This is a bill for a clinic visit on October 3. Your insurance paid part of it. You still owe the rest.',
  urgency: 'high',
  actions: [
    { what: 'Pay $1,284.50, or call to set up a monthly payment plan', deadline: '2026-12-14' },
    { what: 'Ask for financial assistance if you cannot pay. The letter says you may qualify', deadline: null },
  ],
  amountDue: { value: 1284.5, currency: 'USD' },
  glossary: [
    { term: 'Patient responsibility', plain: 'The part of the bill you pay yourself' },
    { term: 'Collections', plain: 'A company that chases unpaid bills. It can hurt your credit' },
  ],
}

const CANNED_ENTITIES = {
  entities: [
    { type: 'NAME', value: 'Maria Okafor' },
    { type: 'ADDRESS', value: '88 Linden Avenue, Apt 4, Oakland, CA 94607' },
  ],
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

function answerFor(request: GenerateRequest): string {
  if (request.jsonSchema === DECODE_JSON_SCHEMA) return JSON.stringify(CANNED_DECODE)
  if (request.jsonSchema === PERSONAL_DETAILS_JSON_SCHEMA) return JSON.stringify(CANNED_ENTITIES)
  return 'Dear Billing Office,\n\nI am writing about my account. [YOUR REQUEST]\n\nThank you,\n[NAME_1]'
}

export function createFixtureInference(): Inference {
  return {
    async generate(request): Promise<InferenceResult> {
      await wait(FIXTURE_DELAY_MS)
      return {
        text: answerFor(request),
        source: request.mode === 'only_in_cloud' ? 'in_cloud' : 'on_device',
      }
    },
    async chat(): Promise<InferenceResult> {
      await wait(FIXTURE_DELAY_MS)
      return {
        text: 'Yes, [NAME_1]. The letter says you can call [PHONE_1] to ask for a payment plan before the due date.',
        source: 'in_cloud',
      }
    },
    deviceModelStatus: async () => 'available',
    downloadDeviceModel: async (onProgress) => onProgress(1),
  }
}
