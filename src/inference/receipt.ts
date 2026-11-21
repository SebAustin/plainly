import type {
  ChatRequest,
  GenerateRequest,
  Inference,
  InferenceResult,
  InferenceSource,
  InferenceTask,
} from './inference'

/**
 * The privacy receipt: one line per model call, recording where it ran and,
 * for cloud calls, the exact text that left the device.
 */
export interface ReceiptEntry {
  id: number
  task: InferenceTask
  source: InferenceSource
  /** Text sent to the cloud. Null for on-device calls: nothing left. */
  sentToCloud: string | null
  /** True when a file (photo or PDF) was sent along with the text. */
  sentFile: boolean
}

let nextId = 1

function entryFor(
  request: GenerateRequest | ChatRequest,
  result: InferenceResult,
  text: string,
  sentFile: boolean,
): ReceiptEntry {
  const inCloud = result.source === 'in_cloud'
  return {
    id: nextId++,
    task: request.task,
    source: result.source,
    // The system instruction travels too (for follow-ups it carries the
    // redacted letter), so the receipt shows it along with the message.
    sentToCloud: inCloud ? `${request.system}\n\n${text}` : null,
    sentFile: inCloud && sentFile,
  }
}

/** Wraps an Inference so every call is reported to `record`. */
export function withReceipt(inference: Inference, record: (entry: ReceiptEntry) => void): Inference {
  return {
    ...inference,
    async generate(request) {
      const result = await inference.generate(request)
      record(entryFor(request, result, request.prompt, Boolean(request.attachment)))
      return result
    },
    async chat(request) {
      const result = await inference.chat(request)
      record(entryFor(request, result, request.message, false))
      return result
    },
  }
}
