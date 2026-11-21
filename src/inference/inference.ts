import type { DeviceModelStatus } from '../core/routing'

/**
 * The inference port. The app talks to models only through this interface;
 * the real adapter is Firebase AI Logic (see firebaseInference.ts).
 */

export type InferenceMode = 'only_on_device' | 'only_in_cloud' | 'prefer_on_device'
export type InferenceSource = 'on_device' | 'in_cloud'

export interface Attachment {
  /** Base64-encoded bytes, without a data: prefix. */
  base64: string
  mimeType: string
}

/** What a model call is for. Shown to the user in the privacy receipt. */
export type InferenceTask =
  | 'Read the letter'
  | 'Find personal details'
  | 'Transcribe the photo'
  | 'Answer a question'
  | 'Draft a reply'
  | 'Prepare the on-device model'

export interface GenerateRequest {
  task: InferenceTask
  mode: InferenceMode
  system: string
  prompt: string
  attachment?: Attachment
  /** When set, the model must answer with JSON matching this schema. */
  jsonSchema?: Record<string, unknown>
}

export interface ChatTurn {
  role: 'user' | 'model'
  text: string
}

export interface ChatRequest {
  task: InferenceTask
  system: string
  history: readonly ChatTurn[]
  message: string
}

export interface InferenceResult {
  text: string
  /** Where the answer was actually produced, as reported by the SDK. */
  source: InferenceSource
}

export interface Inference {
  generate(request: GenerateRequest): Promise<InferenceResult>
  /** Multi-turn chat. Cloud only: the on-device model is single-turn. */
  chat(request: ChatRequest): Promise<InferenceResult>
  deviceModelStatus(): Promise<DeviceModelStatus>
  /** Starts the on-device model download. Must be called from a user gesture. */
  downloadDeviceModel(onProgress: (fraction: number) => void): Promise<void>
}
