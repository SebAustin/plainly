import type { FirebaseOptions } from 'firebase/app'

/**
 * Firebase web config comes from Vite env vars (see .env.example).
 * These values identify the project; they are not secrets. Access is
 * protected by App Check and Firestore security rules.
 */

const env = import.meta.env

const REQUIRED_KEYS = [
  'VITE_FIREBASE_API_KEY',
  'VITE_FIREBASE_AUTH_DOMAIN',
  'VITE_FIREBASE_PROJECT_ID',
  'VITE_FIREBASE_APP_ID',
] as const

export const missingConfigKeys: readonly string[] = REQUIRED_KEYS.filter((key) => !env[key])

export const isFirebaseConfigured = missingConfigKeys.length === 0

export const firebaseOptions: FirebaseOptions = {
  apiKey: env.VITE_FIREBASE_API_KEY,
  authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: env.VITE_FIREBASE_APP_ID,
}

export const appCheckConfig = {
  recaptchaEnterpriseSiteKey: env.VITE_RECAPTCHA_ENTERPRISE_SITE_KEY as string | undefined,
  /** A registered debug token, or "true" to have the SDK print a new one to the console. */
  debugToken: env.VITE_APPCHECK_DEBUG_TOKEN as string | undefined,
}

/** Remote Config parameters and their in-app defaults. */
export const REMOTE_CONFIG_DEFAULTS = {
  cloud_model: 'gemini-3.5-flash-lite',
  device_token_budget: 6000,
} as const
