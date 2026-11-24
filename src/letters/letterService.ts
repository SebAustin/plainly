import { DECODE_JSON_SCHEMA, parseDecode, type Decode } from '../core/decode'
import { PERSONAL_DETAILS_JSON_SCHEMA, parsePersonalDetails } from '../core/personalDetails'
import { redact, restore, type DetectedEntity, type Vault } from '../core/redaction'
import {
  chooseRoute,
  type BlockReason,
  type Environment,
  type LetterInputShape,
  type RedactionLevel,
  type Route,
} from '../core/routing'
import type {
  Attachment,
  ChatTurn,
  GenerateRequest,
  Inference,
  InferenceSource,
} from '../inference/inference'
import * as prompts from './prompts'

/**
 * The letter service runs each task where `chooseRoute` says it may run, and
 * guarantees the invariant the product is built on: text only reaches the
 * cloud after it has been through `redact`.
 */

export type LetterInput =
  | { kind: 'text'; text: string }
  | { kind: 'image'; attachment: Attachment }
  | { kind: 'pdf'; attachment: Attachment }

/** Exactly what the cloud is allowed to see of a letter, plus the key to undo it locally. */
export interface CloudContext {
  redactedText: string
  vault: Vault
  level: RedactionLevel
  /**
   * The on-device model was asked for names and addresses but its answer could
   * not be read, so only pattern rules ran. Sending needs the reader's consent.
   */
  unreadableNames: boolean
}

/** Thrown when text would reach the cloud with names visible and the reader has not agreed. */
export class NeedsCloudConsentError extends Error {
  constructor() {
    super('Names and addresses could not be hidden; the reader has to agree before sending.')
    this.name = 'NeedsCloudConsentError'
  }
}

export interface DecodedLetter {
  decode: Decode
  source: InferenceSource
  route: Route
  /** Set when the decode itself went through the cloud. */
  cloudContext: CloudContext | null
}

export type DecodeLetterResult =
  | { ok: true; letter: DecodedLetter }
  | { ok: false; reason: BlockReason | 'unreadable-answer' }

export interface FollowUpReply {
  answer: string
  /** This exchange exactly as the cloud saw it; append to the history of the next call. */
  cloudTurns: readonly ChatTurn[]
  context: CloudContext
}

const MAX_DECODE_ATTEMPTS = 2
const MAX_PERSONAL_DETAILS_ATTEMPTS = 2
const CHARACTERS_PER_TOKEN = 4

function shapeOf(input: LetterInput): LetterInputShape {
  switch (input.kind) {
    case 'text':
      return { kind: 'text', characters: input.text.length }
    case 'image':
      return { kind: 'image', mimeType: input.attachment.mimeType }
    case 'pdf':
      return { kind: 'pdf' }
  }
}

function splitIntoChunks(text: string, size: number): string[] {
  const chunks: string[] = []
  for (let start = 0; start < text.length; start += size) {
    chunks.push(text.slice(start, start + size))
  }
  return chunks
}

/** Asks the on-device model for one chunk's names and addresses; null if no attempt was readable. */
async function personalDetailsIn(
  chunk: string,
  inference: Inference,
): Promise<DetectedEntity[] | null> {
  for (let attempt = 0; attempt < MAX_PERSONAL_DETAILS_ATTEMPTS; attempt += 1) {
    const result = await inference.generate({
      task: 'Find personal details',
      mode: 'only_on_device',
      system: prompts.PERSONAL_DETAILS_SYSTEM,
      prompt: prompts.PERSONAL_DETAILS_PROMPT(chunk),
      jsonSchema: PERSONAL_DETAILS_JSON_SCHEMA,
    })
    const found = parsePersonalDetails(result.text)
    if (found) return found
  }
  return null
}

/**
 * Asks the on-device model for names and addresses, one budget-sized chunk at
 * a time. Returns null if any chunk could not be read.
 */
async function findPersonalDetails(
  text: string,
  environment: Environment,
  inference: Inference,
): Promise<DetectedEntity[] | null> {
  const chunkSize = environment.deviceTokenBudget * CHARACTERS_PER_TOKEN
  const found: DetectedEntity[] = []
  for (const chunk of splitIntoChunks(text, chunkSize)) {
    const entities = await personalDetailsIn(chunk, inference)
    if (!entities) return null
    found.push(...entities)
  }
  return found
}

/**
 * Redacts text for the cloud. If the on-device model was meant to find names
 * but its answer could not be read, the context says so honestly: it is marked
 * pattern-rules only, and sending it then needs the reader's consent.
 */
async function redactForCloud(
  text: string,
  level: RedactionLevel,
  environment: Environment,
  inference: Inference,
): Promise<CloudContext> {
  const found =
    level === 'device-assisted' ? await findPersonalDetails(text, environment, inference) : []
  const unreadableNames = found === null
  const { redacted, vault } = redact(text, found ?? [])
  return {
    redactedText: redacted,
    vault,
    level: unreadableNames ? 'rules-only' : level,
    unreadableNames,
  }
}

function needsConsent(context: CloudContext, hasCloudConsent: boolean): boolean {
  return context.unreadableNames && !hasCloudConsent
}

function restoreDecode(decode: Decode, vault: Vault): Decode {
  return {
    ...decode,
    sender: restore(decode.sender, vault),
    summary: restore(decode.summary, vault),
    actions: decode.actions.map((action) => ({ ...action, what: restore(action.what, vault) })),
    glossary: decode.glossary.map((entry) => ({
      term: restore(entry.term, vault),
      plain: restore(entry.plain, vault),
    })),
  }
}

async function generateDecode(
  request: Omit<GenerateRequest, 'task' | 'system' | 'jsonSchema'>,
  inference: Inference,
): Promise<{ decode: Decode; source: InferenceSource } | null> {
  for (let attempt = 0; attempt < MAX_DECODE_ATTEMPTS; attempt += 1) {
    const result = await inference.generate({
      ...request,
      task: 'Read the letter',
      system: prompts.DECODER_SYSTEM,
      jsonSchema: DECODE_JSON_SCHEMA,
    })
    const parsed = parseDecode(result.text)
    if (parsed.ok) return { decode: parsed.decode, source: result.source }
  }
  return null
}

function decodeRequest(input: LetterInput, mode: GenerateRequest['mode'], text?: string) {
  return input.kind === 'text'
    ? { mode, prompt: prompts.DECODE_TEXT_PROMPT(text ?? input.text) }
    : { mode, prompt: prompts.DECODE_FILE_PROMPT, attachment: input.attachment }
}

export async function decodeLetter(
  input: LetterInput,
  environment: Environment,
  inference: Inference,
): Promise<DecodeLetterResult> {
  const route = chooseRoute({ kind: 'decode', input: shapeOf(input) }, environment)
  if (route.run === 'blocked') return { ok: false, reason: route.reason }
  if (route.run === 'either') throw new Error('Decoding never uses a prefer_* mode.')

  if (route.run === 'device') {
    const result = await generateDecode(decodeRequest(input, route.mode), inference)
    if (!result) return { ok: false, reason: 'unreadable-answer' }
    return { ok: true, letter: { ...result, route, cloudContext: null } }
  }

  // Cloud. Text is redacted first; files only get here with explicit consent.
  const cloudContext =
    input.kind === 'text'
      ? await redactForCloud(input.text, route.redaction, environment, inference)
      : null
  if (cloudContext && needsConsent(cloudContext, environment.hasCloudConsent)) {
    return { ok: false, reason: 'needs-cloud-consent' }
  }
  const result = await generateDecode(
    decodeRequest(input, route.mode, cloudContext?.redactedText),
    inference,
  )
  if (!result) return { ok: false, reason: 'unreadable-answer' }
  const decode = cloudContext ? restoreDecode(result.decode, cloudContext.vault) : result.decode
  return { ok: true, letter: { decode, source: result.source, route, cloudContext } }
}

/** Describes a decode in words, for when the letter itself has no text the cloud may see. */
function decodeAsText(decode: Decode): string {
  const actions = decode.actions
    .map((action) => `- ${action.what}${action.deadline ? ` (by ${action.deadline})` : ''}`)
    .join('\n')
  return `From: ${decode.sender}\n${decode.summary}\nWhat to do:\n${actions || '- Nothing required'}`
}

/**
 * Builds the redacted view of a letter that follow-up and reply drafting send
 * to the cloud. A photo is first transcribed on device, so its pixels stay local.
 */
export async function prepareCloudContext(
  input: LetterInput,
  environment: Environment,
  inference: Inference,
  decode?: Decode,
): Promise<CloudContext> {
  const hasDevice = environment.deviceModel !== 'unavailable'
  const level: RedactionLevel = hasDevice ? 'device-assisted' : 'rules-only'

  if (input.kind === 'text') return redactForCloud(input.text, level, environment, inference)

  const canTranscribe = hasDevice && input.kind === 'image'
  if (canTranscribe) {
    const transcript = await inference.generate({
      task: 'Transcribe the photo',
      mode: 'only_on_device',
      system: prompts.TRANSCRIBE_SYSTEM,
      prompt: prompts.TRANSCRIBE_PROMPT,
      attachment: input.attachment,
    })
    return redactForCloud(transcript.text, level, environment, inference)
  }

  // No way to read the file locally: fall back to the decode we already have.
  return redactForCloud(decode ? decodeAsText(decode) : '', level, environment, inference)
}

export async function askFollowUp(
  context: CloudContext,
  history: readonly ChatTurn[],
  question: string,
  inference: Inference,
  hasCloudConsent = false,
): Promise<FollowUpReply> {
  if (needsConsent(context, hasCloudConsent)) throw new NeedsCloudConsentError()
  const { redacted, vault } = redact(question, [], context.vault)
  const result = await inference.chat({
    task: 'Answer a question',
    system: prompts.FOLLOW_UP_SYSTEM(context.redactedText),
    history,
    message: redacted,
  })
  return {
    answer: restore(result.text, vault),
    cloudTurns: [
      { role: 'user', text: redacted },
      { role: 'model', text: result.text },
    ],
    context: { ...context, vault },
  }
}

export interface DraftedReply {
  text: string
  source: InferenceSource
}

/** Drafts a reply on redacted text. The SDK chooses device or cloud (prefer_on_device). */
export async function draftReply(
  context: CloudContext,
  goal: string,
  environment: Environment,
  inference: Inference,
): Promise<DraftedReply | { blocked: BlockReason }> {
  const route = chooseRoute({ kind: 'draft-reply' }, environment)
  if (route.run === 'blocked') return { blocked: route.reason }
  if (route.run === 'cloud') throw new Error('Reply drafting never forces the cloud.')
  // A prefer-on-device draft may still fall back to the cloud.
  if (needsConsent(context, environment.hasCloudConsent)) return { blocked: 'needs-cloud-consent' }

  const redactedGoal = redact(goal, [], context.vault)
  const result = await inference.generate({
    task: 'Draft a reply',
    mode: route.mode,
    system: prompts.DRAFT_REPLY_SYSTEM,
    prompt: prompts.DRAFT_REPLY_PROMPT(context.redactedText, redactedGoal.redacted),
  })
  return { text: restore(result.text, redactedGoal.vault).trim(), source: result.source }
}
