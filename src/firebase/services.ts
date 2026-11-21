import { initializeApp, type FirebaseApp } from 'firebase/app'
import { getAI, GoogleAIBackend, type AI } from 'firebase/ai'
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from 'firebase/app-check'
import { getAuth, onAuthStateChanged, signInAnonymously, type Auth } from 'firebase/auth'
import {
  initializeFirestore,
  persistentLocalCache,
  type Firestore,
} from 'firebase/firestore'
import { fetchAndActivate, getRemoteConfig, getValue } from 'firebase/remote-config'
import { appCheckConfig, firebaseOptions, REMOTE_CONFIG_DEFAULTS } from './config'

export interface RuntimeSettings {
  cloudModel: string
  deviceTokenBudget: number
}

export interface FirebaseServices {
  app: FirebaseApp
  ai: AI
  auth: Auth
  db: Firestore
  /** Resolves with the anonymous user's id once sign-in completes. */
  userId: Promise<string>
  /** Resolves with Remote Config values, or the defaults if the fetch fails. */
  settings: Promise<RuntimeSettings>
}

declare global {
  interface Window {
    FIREBASE_APPCHECK_DEBUG_TOKEN?: string | boolean
  }
}

const REMOTE_CONFIG_FETCH_INTERVAL_MS = 60 * 60 * 1000
const DEV_PLACEHOLDER_SITE_KEY = 'debug-provider-only'

function startAppCheck(app: FirebaseApp): void {
  const { debugToken, recaptchaEnterpriseSiteKey } = appCheckConfig
  if (debugToken) {
    // Must be set before initializeAppCheck. "true" makes the SDK print a
    // fresh token to the console for registering in the Firebase console.
    window.FIREBASE_APPCHECK_DEBUG_TOKEN = debugToken === 'true' ? true : debugToken
  }
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(recaptchaEnterpriseSiteKey ?? DEV_PLACEHOLDER_SITE_KEY),
    isTokenAutoRefreshEnabled: true,
  })
}

function signIn(auth: Auth): Promise<string> {
  return new Promise((resolve, reject) => {
    const stop = onAuthStateChanged(
      auth,
      (user) => {
        if (user) {
          stop()
          resolve(user.uid)
        }
      },
      reject,
    )
    signInAnonymously(auth).catch(reject)
  })
}

async function loadSettings(app: FirebaseApp): Promise<RuntimeSettings> {
  const defaults: RuntimeSettings = {
    cloudModel: REMOTE_CONFIG_DEFAULTS.cloud_model,
    deviceTokenBudget: REMOTE_CONFIG_DEFAULTS.device_token_budget,
  }
  try {
    const remoteConfig = getRemoteConfig(app)
    remoteConfig.settings.minimumFetchIntervalMillis = REMOTE_CONFIG_FETCH_INTERVAL_MS
    remoteConfig.defaultConfig = { ...REMOTE_CONFIG_DEFAULTS }
    await fetchAndActivate(remoteConfig)
    const budget = getValue(remoteConfig, 'device_token_budget').asNumber()
    return {
      cloudModel: getValue(remoteConfig, 'cloud_model').asString() || defaults.cloudModel,
      deviceTokenBudget: budget > 0 ? budget : defaults.deviceTokenBudget,
    }
  } catch (error) {
    // Offline or blocked: the app must still work on device with defaults.
    console.warn('Remote Config unavailable, using defaults.', error)
    return defaults
  }
}

let services: FirebaseServices | undefined

export function getFirebaseServices(): FirebaseServices {
  if (services) return services

  const app = initializeApp(firebaseOptions)
  startAppCheck(app)
  const auth = getAuth(app)

  services = {
    app,
    ai: getAI(app, { backend: new GoogleAIBackend() }),
    auth,
    db: initializeFirestore(app, { localCache: persistentLocalCache() }),
    userId: signIn(auth),
    settings: loadSettings(app),
  }
  return services
}
