/**
 * Routing decides where each task runs. It is the product's privacy policy,
 * written as a pure function:
 *
 *  - Raw letters are only ever read on the device.
 *  - The cloud only sees text that was redacted first.
 *  - Anything that cannot be redacted (photos, PDFs) needs explicit consent.
 *
 * The `mode` values are Firebase AI Logic `InferenceMode` strings.
 */

export type DeviceModelStatus = 'available' | 'downloadable' | 'downloading' | 'unavailable'

export interface Environment {
  deviceModel: DeviceModelStatus
  isOnline: boolean
  /** The user agreed to send this unredactable file to the cloud. */
  hasCloudConsent: boolean
  /** Input tokens the on-device model can take (from Remote Config). */
  deviceTokenBudget: number
}

export type LetterInputShape =
  | { kind: 'text'; characters: number }
  | { kind: 'image'; mimeType: string }
  | { kind: 'pdf' }

export type Task =
  | { kind: 'decode'; input: LetterInputShape }
  | { kind: 'find-personal-details'; characters: number }
  | { kind: 'follow-up' }
  | { kind: 'draft-reply' }

/** How text is redacted before the cloud sees it. */
export type RedactionLevel = 'device-assisted' | 'rules-only' | 'none'

export type BlockReason = 'offline' | 'needs-cloud-consent'

export type Route =
  | { run: 'device'; mode: 'only_on_device' }
  | { run: 'cloud'; mode: 'only_in_cloud'; redaction: RedactionLevel }
  | { run: 'either'; mode: 'prefer_on_device'; redaction: RedactionLevel }
  | { run: 'blocked'; reason: BlockReason }

const CHARACTERS_PER_TOKEN = 4
const DEVICE_IMAGE_TYPES: readonly string[] = ['image/jpeg', 'image/png']

const ON_DEVICE: Route = { run: 'device', mode: 'only_on_device' }
const OFFLINE: Route = { run: 'blocked', reason: 'offline' }

export function estimateTokens(characters: number): number {
  return Math.ceil(characters / CHARACTERS_PER_TOKEN)
}

/** A downloading model counts: `only_on_device` waits for it instead of leaking to the cloud. */
function hasDeviceModel(environment: Environment): boolean {
  return environment.deviceModel !== 'unavailable'
}

function redactionFor(environment: Environment): RedactionLevel {
  return hasDeviceModel(environment) ? 'device-assisted' : 'rules-only'
}

function cloudWithRedactedText(environment: Environment): Route {
  if (!environment.isOnline) return OFFLINE
  return { run: 'cloud', mode: 'only_in_cloud', redaction: redactionFor(environment) }
}

function cloudWithUnredactableFile(environment: Environment): Route {
  if (!environment.isOnline) return OFFLINE
  if (!environment.hasCloudConsent) return { run: 'blocked', reason: 'needs-cloud-consent' }
  return { run: 'cloud', mode: 'only_in_cloud', redaction: 'none' }
}

function fitsOnDevice(input: LetterInputShape, environment: Environment): boolean {
  if (!hasDeviceModel(environment)) return false
  switch (input.kind) {
    case 'text':
      return estimateTokens(input.characters) <= environment.deviceTokenBudget
    case 'image':
      return DEVICE_IMAGE_TYPES.includes(input.mimeType)
    case 'pdf':
      return false
  }
}

function routeDecode(input: LetterInputShape, environment: Environment): Route {
  if (fitsOnDevice(input, environment)) return ON_DEVICE
  return input.kind === 'text'
    ? cloudWithRedactedText(environment)
    : cloudWithUnredactableFile(environment)
}

export function chooseRoute(task: Task, environment: Environment): Route {
  switch (task.kind) {
    case 'decode':
      return routeDecode(task.input, environment)
    case 'find-personal-details':
      return ON_DEVICE
    case 'follow-up':
      return cloudWithRedactedText(environment)
    case 'draft-reply':
      if (!environment.isOnline) return hasDeviceModel(environment) ? ON_DEVICE : OFFLINE
      return { run: 'either', mode: 'prefer_on_device', redaction: redactionFor(environment) }
  }
}
