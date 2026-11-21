# Plainly

**Official mail, in plain words. Read privately on your device.**

Plainly explains confusing official letters (medical bills, tax notices, immigration and benefits mail) to the people who receive them. You paste or photograph a letter and get back what it is, what you have to do, by when, and how much it costs.

Built for [#BuildHybridAI 2026](https://firebasehybridaihackathon.devpost.com/) on **Firebase AI Logic hybrid inference**. Platform: Web (Chrome).

## The problem

Official letters are written for the institution, not the reader. People miss deadlines, lose benefits and pay late fees because a letter was hard to understand. The obvious fix, pasting the letter into a chatbot, means uploading your name, address, account numbers and diagnosis to a server.

## How Plainly uses hybrid inference

Most hybrid apps treat the cloud as a fallback. Plainly treats the on-device model as a **privacy gate in front of the cloud**. Each task has an explicit Firebase AI Logic `InferenceMode`, chosen by one pure function ([src/core/routing.ts](src/core/routing.ts)):

| Task | Mode | Why |
| --- | --- | --- |
| Read the letter (text or photo) | `ONLY_ON_DEVICE` | The raw letter never leaves the device. `PREFER_ON_DEVICE` could silently upload it. |
| Find names and addresses | `ONLY_ON_DEVICE` | Gemini Nano lists personal details so they can be hidden. |
| Answer follow-up questions | `ONLY_IN_CLOUD` | Multi-turn chat is not available on device. The cloud only receives redacted text. |
| Draft a reply | `PREFER_ON_DEVICE` | Works on already-redacted text, so the SDK may pick either side. |
| Letter too long for the device | `ONLY_IN_CLOUD` | Redacted on device first, then sent. |
| PDF, or photo with no on-device model | blocked until consent | A file cannot be redacted, so the user must agree first. |

Personal details are swapped for placeholders such as `[NAME_1]` before any cloud call. The mapping stays in memory on the device, and cloud answers are rehydrated locally ([src/core/redaction.ts](src/core/redaction.ts)).

Every model call is logged in an on-screen **privacy receipt** showing where it ran (from the SDK's `response.inferenceSource`) and, for cloud calls, the exact text that was sent.

### Where Firebase AI Logic is called

- [src/inference/firebaseInference.ts](src/inference/firebaseInference.ts): `getGenerativeModel` with `mode`, `inCloudParams` and `onDeviceParams`; `generateContent`, `startChat`, `initializeDeviceModel`, `inferenceSource`.
- [src/firebase/services.ts](src/firebase/services.ts): `getAI` with `GoogleAIBackend`, plus App Check, Anonymous Auth, Firestore and Remote Config.

One JSON Schema (derived from a Zod schema in [src/core/decode.ts](src/core/decode.ts)) constrains both models: `responseJsonSchema` in the cloud and the Prompt API's `responseConstraint` on device. The answer is validated before the UI shows it, and a deadline that is not a real date is dropped.

### Other Firebase products

- **App Check** protects the AI Logic endpoint (debug token locally, reCAPTCHA Enterprise when hosted).
- **Anonymous Authentication** gives each visitor a private space with no sign-up.
- **Firestore** stores tracked deadlines only: sender, category, date, amount. The letter and its summary are never stored. Rules are in [firestore.rules](firestore.rules).
- **Remote Config** sets the cloud model (`cloud_model`) and the on-device token budget (`device_token_budget`) without a redeploy.

## Features

- Paste text, or add a JPEG/PNG photo, and get a plain-language reading with a countdown to the deadline.
- Checklist of required actions and a glossary of the jargon used.
- Follow-up questions and reply drafting on redacted text.
- Privacy receipt for every model call.
- Works offline for reading letters once the on-device model is installed.
- Track a deadline across devices without storing the letter.

## Run it

Requirements: Node 20+, pnpm, Chrome desktop 139+.

```bash
pnpm install
```

```bash
bash scripts/setup-firebase.sh
```

The setup script walks through creating the Firebase project, enabling AI Logic, Anonymous Auth and Firestore, registering an App Check debug token, and turning on Gemini Nano in Chrome. It writes `.env.local`. To do it by hand instead, copy `.env.example` to `.env.local` and fill it in.

```bash
pnpm dev
```

To look at the interface without a Firebase project, open the dev server with `?fixture` appended to the URL. That mode uses canned answers, says so on screen, and is not available in production builds.

Do not put the project in a folder whose path contains `#`; Vite cannot resolve files there.

### Checks

```bash
pnpm test
```

```bash
pnpm build
```

```bash
pnpm lint
```

## How it is organised

```text
src/
  core/        Pure domain logic, unit tested: routing, redaction, decode parsing
  inference/   The Inference port, the Firebase AI Logic adapter, the privacy receipt
  letters/     Use cases: decode a letter, follow up, draft a reply, track a deadline
  firebase/    App, App Check, Auth, Firestore, Remote Config
  features/    UI by feature: composer, decode, followup, receipt, deadlines, status
  app/         Runtime wiring and the usePlainly hook
```

The tests in [src/letters/letterService.test.ts](src/letters/letterService.test.ts) run the use cases against a recording fake model and assert that no name or email ever appears in a request sent to the cloud.

## Limits

- Redaction is best effort. Pattern rules catch emails, phone numbers, US social security numbers and long account numbers; names and addresses depend on the on-device model finding them. The receipt shows what was sent so you can check.
- Without an on-device model (other browsers, unsupported hardware), text falls back to the cloud with pattern-only redaction, and the interface says so.
- Plainly explains letters. It is not legal, medical or financial advice.
- English only for now.

## License

[Apache-2.0](LICENSE)
