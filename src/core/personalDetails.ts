import { z } from 'zod'
import { parseJson } from './decode'
import type { DetectedEntity } from './redaction'

/**
 * Names and postal addresses cannot be found with patterns, so the on-device
 * model is asked to list them. Its answer feeds `redact`.
 */

const personalDetailsSchema = z.object({
  entities: z
    .array(
      z.object({
        type: z.enum(['NAME', 'ADDRESS']),
        value: z.string().describe('The exact text as it appears in the letter'),
      }),
    )
    .describe('Every person name and postal address in the letter. Not organisations'),
})

export const PERSONAL_DETAILS_JSON_SCHEMA: Record<string, unknown> =
  z.toJSONSchema(personalDetailsSchema)

/**
 * Returns the entities the model found. A malformed answer yields an empty
 * list: pattern-based redaction still runs, and the UI reports the lower level.
 */
export function parsePersonalDetails(raw: string): DetectedEntity[] {
  const json = parseJson(raw)
  if (!json.ok) return []
  const parsed = personalDetailsSchema.safeParse(json.value)
  return parsed.success ? parsed.data.entities : []
}
