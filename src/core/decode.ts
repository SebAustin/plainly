import { z } from 'zod'

/**
 * A Decode is the plain-language reading of one letter: what it is, what the
 * reader has to do, by when, and how much it costs.
 *
 * The same schema is handed to both models (on-device via the Prompt API's
 * `responseConstraint`, cloud via `responseJsonSchema`), and whatever comes
 * back is validated here before the UI trusts it.
 */

export const LETTER_CATEGORIES = [
  'bill',
  'medical',
  'tax',
  'immigration',
  'benefits',
  'legal',
  'housing',
  'other',
] as const

export const URGENCY_LEVELS = ['low', 'medium', 'high'] as const

const decodeSchema = z.object({
  sender: z.string().describe('Who sent the letter (organisation or office)'),
  category: z.enum(LETTER_CATEGORIES),
  summary: z
    .string()
    .describe('Two or three short sentences, at a 12-year-old reading level, saying what this letter is'),
  urgency: z.enum(URGENCY_LEVELS).describe('high if money, rights or benefits are lost by not acting'),
  actions: z
    .array(
      z.object({
        what: z.string().describe('One thing the reader must do, starting with a verb'),
        deadline: z
          .string()
          .nullable()
          .describe('Deadline as YYYY-MM-DD, or null if the letter gives none'),
      }),
    )
    .describe('What the reader must do, most important first. Empty if nothing is required'),
  amountDue: z
    .object({ value: z.number(), currency: z.string().describe('ISO 4217 code, e.g. USD') })
    .nullable()
    .describe('Money the reader owes, or null'),
  glossary: z
    .array(z.object({ term: z.string(), plain: z.string() }))
    .describe('Up to four jargon terms from the letter, explained in plain words'),
})

export type Decode = z.infer<typeof decodeSchema>
export type LetterCategory = (typeof LETTER_CATEGORIES)[number]
export type Urgency = (typeof URGENCY_LEVELS)[number]

/** JSON Schema given to both models as the structured-output constraint. */
export const DECODE_JSON_SCHEMA: Record<string, unknown> = z.toJSONSchema(decodeSchema)

export type ParseDecodeResult =
  | { ok: true; decode: Decode }
  | { ok: false; error: 'not-json' | 'wrong-shape' }

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/
const CODE_FENCE = /^```(?:json)?\s*|\s*```$/g
const MS_PER_DAY = 86_400_000

function parseIsoDate(value: string): Date | null {
  if (!ISO_DATE.test(value)) return null
  const [year, month, day] = value.split('-').map(Number)
  const date = new Date(year, month - 1, day)
  const isRealDate = date.getMonth() === month - 1 && date.getDate() === day
  return isRealDate ? date : null
}

export function parseJson(raw: string): { ok: true; value: unknown } | { ok: false } {
  try {
    return { ok: true, value: JSON.parse(raw.trim().replace(CODE_FENCE, '')) }
  } catch {
    return { ok: false }
  }
}

export function parseDecode(raw: string): ParseDecodeResult {
  const json = parseJson(raw)
  if (!json.ok) return { ok: false, error: 'not-json' }

  const parsed = decodeSchema.safeParse(json.value)
  if (!parsed.success) return { ok: false, error: 'wrong-shape' }

  // A model may write "within 30 days" where a date belongs. An invented
  // deadline is worse than none, so anything that is not a real date is dropped.
  const actions = parsed.data.actions.map((action) => ({
    ...action,
    deadline: action.deadline && parseIsoDate(action.deadline) ? action.deadline : null,
  }))

  return { ok: true, decode: { ...parsed.data, actions } }
}

/** Whole calendar days from `now` to an ISO deadline. Negative once it has passed. */
export function daysUntil(isoDate: string, now: Date = new Date()): number {
  const deadline = parseIsoDate(isoDate)
  if (!deadline) return Number.NaN
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return Math.round((deadline.getTime() - today.getTime()) / MS_PER_DAY)
}

/** The soonest deadline across all actions, or null if the letter has none. */
export function nextDeadline(decode: Decode): string | null {
  const deadlines = decode.actions.flatMap((action) => (action.deadline ? [action.deadline] : []))
  return deadlines.length > 0 ? [...deadlines].sort()[0] : null
}
