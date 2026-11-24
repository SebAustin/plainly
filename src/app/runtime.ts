import { isFirebaseConfigured, REMOTE_CONFIG_DEFAULTS } from '../firebase/config'
import { getFirebaseServices } from '../firebase/services'
import { createFirebaseInference } from '../inference/firebaseInference'
import { createFixtureInference } from '../inference/fixtureInference'
import type { Inference } from '../inference/inference'
import { createDeadlineStore, type DeadlineStore } from '../letters/deadlineStore'

/**
 * The runtime wires the app to its outside world. There are three kinds:
 *  - firebase:     the real thing (Firebase AI Logic, Auth, Firestore, Remote Config)
 *  - fixture:      canned model answers, dev server only, opt-in with ?fixture
 *  - unconfigured: no Firebase config found; the app explains how to set it up
 */
export type Runtime =
  | {
      kind: 'firebase' | 'fixture'
      inference: Inference
      deadlineStore: Promise<DeadlineStore> | null
      deviceTokenBudget: Promise<number>
    }
  | { kind: 'unconfigured' }

function isFixtureRequested(): boolean {
  return import.meta.env.DEV && new URLSearchParams(window.location.search).has('fixture')
}

export function createRuntime(): Runtime {
  if (isFixtureRequested()) {
    return {
      kind: 'fixture',
      // ?fixture=unreadable-names makes the canned on-device model fail to list
      // names, to exercise the consent prompt.
      inference: createFixtureInference({
        unreadableNames:
          new URLSearchParams(window.location.search).get('fixture') === 'unreadable-names',
      }),
      deadlineStore: null,
      deviceTokenBudget: Promise.resolve(REMOTE_CONFIG_DEFAULTS.device_token_budget),
    }
  }
  if (!isFirebaseConfigured) return { kind: 'unconfigured' }

  const services = getFirebaseServices()
  return {
    kind: 'firebase',
    inference: createFirebaseInference(services.ai, async () => (await services.settings).cloudModel),
    deadlineStore: services.userId.then((userId) => createDeadlineStore(services.db, userId)),
    deviceTokenBudget: services.settings.then((settings) => settings.deviceTokenBudget),
  }
}
