/**
 * Redaction is the privacy gate between a letter and the cloud.
 *
 * Personal details are swapped for stable placeholders ([NAME_1], [EMAIL_1]…)
 * before any text leaves the device. The mapping (the "vault") never leaves
 * the device, so cloud answers can be rehydrated locally with `restore`.
 */

export type EntityType = 'NAME' | 'ADDRESS' | 'EMAIL' | 'PHONE' | 'ID' | 'ACCOUNT'

/** A personal detail found by the on-device model (names, addresses…). */
export interface DetectedEntity {
  type: EntityType
  value: string
}

/** Placeholder → original value. Stays on the device. */
export type Vault = Readonly<Record<string, string>>

export interface Redaction {
  redacted: string
  vault: Vault
}

interface Match {
  start: number
  end: number
  type: EntityType
  priority: number
}

const MIN_ENTITY_LENGTH = 3
const SEPARATORS = /[\s,]+/

/** Pattern rules, in priority order: earlier rules win when spans tie. */
const PATTERN_RULES: ReadonlyArray<{ type: EntityType; pattern: RegExp }> = [
  { type: 'EMAIL', pattern: /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g },
  { type: 'ID', pattern: /\b\d{3}-\d{2}-\d{4}\b/g },
  {
    type: 'PHONE',
    pattern: /(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\b\d{3})[\s.-]?\d{3}[\s.-]?\d{4}\b/g,
  },
  { type: 'ACCOUNT', pattern: /\b\d(?:[ -]?\d){7,}\b/g },
]

const PLACEHOLDER_PATTERN = /\[[A-Z]+_\d+\]/g

function escapeForRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function findAll(text: string, pattern: RegExp, type: EntityType, priority: number): Match[] {
  return Array.from(text.matchAll(pattern), (found) => ({
    start: found.index,
    end: found.index + found[0].length,
    type,
    priority,
  }))
}

function findEntityMatches(text: string, entities: readonly DetectedEntity[]): Match[] {
  return entities
    .map((entity) => ({ ...entity, value: entity.value.trim() }))
    .filter((entity) => entity.value.length >= MIN_ENTITY_LENGTH)
    .flatMap((entity) => {
      // Models tidy what they copy: line breaks become commas or spaces. Match
      // the words in order and accept any mix of whitespace and commas between.
      const words = entity.value.split(SEPARATORS).filter(Boolean).map(escapeForRegExp)
      if (words.length === 0) return []
      // Model-found entities outrank pattern rules (priority -1).
      return findAll(text, new RegExp(words.join('[\\s,]+'), 'gi'), entity.type, -1)
    })
}

function findPatternMatches(text: string): Match[] {
  return PATTERN_RULES.flatMap((rule, priority) =>
    findAll(text, rule.pattern, rule.type, priority),
  )
}

/** Keeps the earliest, then longest, then highest-priority match of any overlap. */
function dropOverlaps(matches: readonly Match[]): Match[] {
  const ordered = [...matches].sort(
    (a, b) => a.start - b.start || b.end - a.end || a.priority - b.priority,
  )
  return ordered.reduce<Match[]>((kept, match) => {
    const previous = kept.at(-1)
    return previous && match.start < previous.end ? kept : [...kept, match]
  }, [])
}

function valueKey(type: EntityType, value: string): string {
  return `${type}:${value.toLowerCase().split(SEPARATORS).filter(Boolean).join(' ')}`
}

function vaultEntries(vault: Vault): Array<{ placeholder: string; type: EntityType; count: number; value: string }> {
  return Object.entries(vault).flatMap(([placeholder, value]) => {
    const parts = /^\[([A-Z]+)_(\d+)\]$/.exec(placeholder)
    return parts
      ? [{ placeholder, type: parts[1] as EntityType, count: Number(parts[2]), value }]
      : []
  })
}

/**
 * Redacts `text`. Pass the letter's `existingVault` when redacting something
 * that belongs to the same conversation (a follow-up question), so the same
 * person keeps the same placeholder across every message the cloud sees.
 */
export function redact(
  text: string,
  entities: readonly DetectedEntity[] = [],
  existingVault: Vault = {},
): Redaction {
  const known = vaultEntries(existingVault)
  const allEntities = [...entities, ...known.map(({ type, value }) => ({ type, value }))]
  const matches = dropOverlaps([
    ...findEntityMatches(text, allEntities),
    ...findPatternMatches(text),
  ])

  const placeholderByValue = new Map(
    known.map((entry) => [valueKey(entry.type, entry.value), entry.placeholder]),
  )
  const countByType = new Map<EntityType, number>()
  for (const entry of known) {
    countByType.set(entry.type, Math.max(countByType.get(entry.type) ?? 0, entry.count))
  }
  const vault: Record<string, string> = { ...existingVault }
  const pieces: string[] = []
  let cursor = 0

  for (const match of matches) {
    const original = text.slice(match.start, match.end)
    const key = valueKey(match.type, original)
    let placeholder = placeholderByValue.get(key)
    if (!placeholder) {
      const count = (countByType.get(match.type) ?? 0) + 1
      countByType.set(match.type, count)
      placeholder = `[${match.type}_${count}]`
      placeholderByValue.set(key, placeholder)
      vault[placeholder] = original
    }
    pieces.push(text.slice(cursor, match.start), placeholder)
    cursor = match.end
  }
  pieces.push(text.slice(cursor))

  return { redacted: pieces.join(''), vault }
}

export function restore(text: string, vault: Vault): string {
  return text.replace(PLACEHOLDER_PATTERN, (placeholder) => vault[placeholder] ?? placeholder)
}
