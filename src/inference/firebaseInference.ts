import {
  getGenerativeModel,
  InferenceMode as FirebaseInferenceMode,
  InferenceSource as FirebaseInferenceSource,
  type AI,
  type GenerativeModel,
  type HybridParams,
  type LanguageModelExpected,
  type Part,
} from 'firebase/ai'
import type { DeviceModelStatus } from '../core/routing'
import type {
  ChatRequest,
  GenerateRequest,
  Inference,
  InferenceMode,
  InferenceResult,
  InferenceSource,
} from './inference'

/**
 * Firebase AI Logic adapter. Every model call in the app goes through
 * `getGenerativeModel` with an explicit hybrid `mode`:
 *
 *  - only_on_device   Gemini Nano in Chrome. Raw letters never leave the device.
 *  - only_in_cloud    Gemini via the Gemini Developer API, on redacted text.
 *  - prefer_on_device The SDK picks: device if it can, cloud fallback if not.
 */

/** The browser's built-in Prompt API, which Firebase AI Logic drives on device. */
interface LanguageModelGlobal {
  availability(options?: object): Promise<DeviceModelStatus>
}

const MODE: Record<InferenceMode, HybridParams['mode']> = {
  only_on_device: FirebaseInferenceMode.ONLY_ON_DEVICE,
  only_in_cloud: FirebaseInferenceMode.ONLY_IN_CLOUD,
  prefer_on_device: FirebaseInferenceMode.PREFER_ON_DEVICE,
}

const TEXT_IO: LanguageModelExpected = { type: 'text', languages: ['en'] }
const IMAGE_INPUT: LanguageModelExpected = { type: 'image' }

function languageModel(): LanguageModelGlobal | undefined {
  return (globalThis as { LanguageModel?: LanguageModelGlobal }).LanguageModel
}

function expectedInputs(hasImage: boolean): LanguageModelExpected[] {
  return hasImage ? [TEXT_IO, IMAGE_INPUT] : [TEXT_IO]
}

function toSource(source: string | undefined, mode: InferenceMode): InferenceSource {
  if (source === FirebaseInferenceSource.ON_DEVICE) return 'on_device'
  if (source === FirebaseInferenceSource.IN_CLOUD) return 'in_cloud'
  // Older SDKs omit inferenceSource; the two strict modes are unambiguous.
  return mode === 'only_on_device' ? 'on_device' : 'in_cloud'
}

export function createFirebaseInference(ai: AI, cloudModel: () => Promise<string>): Inference {
  async function buildModel(request: GenerateRequest): Promise<GenerativeModel> {
    const hasImage = request.attachment?.mimeType.startsWith('image/') ?? false
    return getGenerativeModel(ai, {
      mode: MODE[request.mode],
      inCloudParams: {
        model: await cloudModel(),
        systemInstruction: request.system,
        generationConfig: request.jsonSchema
          ? { responseMimeType: 'application/json', responseJsonSchema: request.jsonSchema }
          : undefined,
      },
      onDeviceParams: {
        createOptions: {
          expectedInputs: expectedInputs(hasImage),
          expectedOutputs: [TEXT_IO],
          initialPrompts: request.system
            ? [{ role: 'system', content: [{ type: 'text', value: request.system }] }]
            : undefined,
        },
        // The SDK does not translate the cloud schema for the Prompt API,
        // so the same JSON Schema is passed as the on-device constraint.
        promptOptions: request.jsonSchema ? { responseConstraint: request.jsonSchema } : undefined,
      },
    })
  }

  return {
    async generate(request: GenerateRequest): Promise<InferenceResult> {
      const model = await buildModel(request)
      const parts: Array<string | Part> = request.attachment
        ? [
            request.prompt,
            {
              type: 'inlineData',
              inlineData: {
                data: request.attachment.base64,
                mimeType: request.attachment.mimeType,
              },
            },
          ]
        : [request.prompt]
      const { response } = await model.generateContent(parts)
      return { text: response.text(), source: toSource(response.inferenceSource, request.mode) }
    },

    async chat(request: ChatRequest): Promise<InferenceResult> {
      const model = getGenerativeModel(ai, {
        mode: FirebaseInferenceMode.ONLY_IN_CLOUD,
        inCloudParams: { model: await cloudModel(), systemInstruction: request.system },
      })
      const chat = model.startChat({
        history: request.history.map((turn) => ({
          role: turn.role,
          parts: [{ type: 'text', text: turn.text }],
        })),
      })
      const { response } = await chat.sendMessage(request.message)
      return { text: response.text(), source: 'in_cloud' }
    },

    async deviceModelStatus(): Promise<DeviceModelStatus> {
      const api = languageModel()
      if (!api) return 'unavailable'
      try {
        return await api.availability({
          expectedInputs: expectedInputs(false),
          expectedOutputs: [TEXT_IO],
        })
      } catch (error) {
        console.warn('Could not query the on-device model.', error)
        return 'unavailable'
      }
    },

    async downloadDeviceModel(onProgress: (fraction: number) => void): Promise<void> {
      const model = await buildModel({
        task: 'Prepare the on-device model',
        mode: 'only_on_device',
        system: '',
        prompt: '',
      })
      await model.initializeDeviceModel(onProgress)
    },
  }
}
