# Devpost submission text: Plainly

Copy each section into the matching field on the Devpost form.

## Project name

Plainly

## Tagline (short description)

Official mail, in plain words. Your letter is read on your device; the cloud only ever sees it with your personal details blacked out.

## Platform

Web (Chrome), with Gemini Nano through Firebase AI Logic.

## Links

- Live app: https://plainly-e1906.web.app
- Code (Apache-2.0): https://github.com/SebAustin/plainly
- Demo video: https://youtu.be/AY9GAYUhc7Y

---

## Inspiration

A medical bill, a tax notice or an immigration letter can cost someone money, benefits or legal status if they misread it, and these letters are written for the institution, not the reader. The people who struggle most with them (recent immigrants, older adults, anyone under stress) are also the people with the most to lose.

The obvious fix is to paste the letter into a chatbot. That means uploading your name, home address, account numbers and sometimes a diagnosis to a server. Hybrid inference makes a better answer possible: let a model on the device read the letter, and only involve the cloud once the personal details are gone.

## What it does

You paste a letter or add a photo of it. Plainly tells you:

- who sent it and what it is, in two or three short sentences
- how many days you have left, and the date
- how much you owe
- what you have to do, as a checklist
- what the jargon means

Then you can ask follow-up questions ("What happens if I miss the deadline?") and have it draft a reply for you.

Every answer carries a stamp saying where it was produced, and a **privacy receipt** lists every model call for that letter. For any call that went to the cloud, you can open the receipt and read the exact text that was sent, with your details shown as black bars.

You can also track a deadline across devices. Only the sender, the date and the amount are stored; the letter never is.

## How we built it: Firebase AI Logic hybrid inference

Most hybrid apps treat the cloud as a fallback for when the device can't cope. Plainly uses the on-device model as a **privacy gate in front of the cloud**. Each task gets an explicit Firebase AI Logic `InferenceMode`, chosen by one pure, unit-tested function (`src/core/routing.ts`):

| Task | Mode | Why |
| --- | --- | --- |
| Read the letter (text or photo) | `ONLY_ON_DEVICE` | The raw letter stays on the device. `PREFER_ON_DEVICE` could silently upload it. |
| Find names and addresses | `ONLY_ON_DEVICE` | Gemini Nano lists personal details so they can be hidden. |
| Transcribe a photo before a follow-up | `ONLY_ON_DEVICE` | The pixels stay local; only redacted text moves on. |
| Answer follow-up questions | `ONLY_IN_CLOUD` | Multi-turn chat isn't available on device. The cloud receives redacted text only. |
| Draft a reply | `PREFER_ON_DEVICE` | It works on already-redacted text, so the SDK may choose either side. |
| A PDF, or a photo with no on-device model | blocked until the user consents | A file can't be redacted, so nothing is sent without an explicit yes. |

How the pieces fit:

- **Redaction and rehydration.** Before any cloud call, emails, phone numbers, ID numbers and account numbers (pattern rules) plus names and addresses (found by Gemini Nano) are replaced with placeholders such as `[NAME_1]`. The mapping stays in memory on the device. When the cloud answers "call [PHONE_1]", Plainly puts the real number back locally.
- **One schema for both models.** A single JSON Schema, derived from a Zod schema, constrains the on-device model (through the Prompt API's `responseConstraint` in `onDeviceParams`) and the cloud model (`responseJsonSchema` in `inCloudParams`). The answer is validated before the UI shows it, and a deadline that isn't a real calendar date is dropped rather than trusted.
- **Honest provenance.** The stamps and the receipt use the SDK's `response.inferenceSource`, so they report where the call really ran, not where we hoped it would.
- **Model download.** `initializeDeviceModel` installs Gemini Nano from a button, with progress.

Other Firebase products:

- **App Check** protects the AI Logic endpoint.
- **Anonymous Authentication** gives each visitor a private space with no sign-up.
- **Cloud Firestore** stores tracked deadlines only, behind per-user security rules that also restrict which fields can be written.
- **Remote Config** sets the cloud model name and the on-device token budget without a redeploy.
- **Firebase Hosting** serves the app with a Content Security Policy.

The app is React, TypeScript and Vite. The routing, redaction and parsing logic is pure and covered by 39 unit tests. One group of tests runs the full flows against a recording fake model and asserts that no name or email appears in anything sent to the cloud.

## Challenges we ran into

- **The SDK doesn't translate schemas for the on-device model.** Cloud structured output is configured in `generationConfig`, but the on-device path needs the schema passed again as a Prompt API `responseConstraint`. We define it once and hand it to both.
- **Models tidy what they copy.** Gemini Nano returned an address on one line with commas, while the letter split it over three lines, so the first redaction pass missed it. The privacy receipt is what exposed this during testing. Matching is now tolerant of whitespace and commas, with a regression test.
- **"Prefer" modes are wrong for private input.** `PREFER_ON_DEVICE` falls back to the cloud without telling you. For raw letters we use `ONLY_ON_DEVICE`, which waits for the model instead of leaking.
- **Keeping a multi-turn chat consistent.** A follow-up question can mention the same person as the letter. Redaction reuses the letter's placeholder table so the cloud sees `[NAME_1]` every time, never two labels for one person.

## Accomplishments that we're proud of

- With real models, a sample medical bill is read on device in roughly 10 to 15 seconds, and a follow-up answer from the cloud returns in 1 to 3 seconds.
- In our tests with that letter, as pasted text and as an image, the name, street address, city, account number, phone number and email all reached the cloud as placeholders.
- The privacy promise is checkable by the user, not just asserted: the receipt shows the exact text sent.

## What we learned

Hybrid inference is more useful as a routing decision than as a fallback. Asking "which model is allowed to see this?" for each task led to a clearer product than asking "which model is available?". We also learned that small on-device models are good at narrow, structured jobs (extract these fields, list these entities), which is exactly what a privacy gate needs.

## What's next for Plainly

- Letters in other languages, with explanations in the reader's own language.
- Better handling of real phone photos: skew, shadows and multi-page letters.
- An iOS app using Apple Foundation Models through the same Firebase AI Logic routing.
- Calendar reminders for tracked deadlines.

## Limits (stated honestly)

- Redaction is best effort. Names and addresses depend on the on-device model finding them, which is why the receipt shows what was sent.
- Without an on-device model, pasted text goes to the cloud with pattern-only redaction, and the interface says so.
- Plainly explains letters. It is not legal, medical or financial advice. English only for now.

## Built with

Firebase AI Logic (hybrid inference), Gemini Nano in Chrome, Gemini Developer API, Firebase App Check, Firebase Authentication, Cloud Firestore, Firebase Remote Config, Firebase Hosting, React, TypeScript, Vite, Zod, Vitest.

## What was built during the submission period

Everything. Plainly is a new project started on November 19, 2026; there was no pre-existing code. It was built with an AI coding assistant (Claude Code) on top of standard open-source libraries.

## Testing instructions for judges

1. Open https://plainly-e1906.web.app in **Chrome desktop 139 or newer**.
2. For on-device reading, enable `chrome://flags/#prompt-api-for-gemini-nano-multimodal-input`, restart Chrome, and click **Install** next to the model status at the top of the page if it isn't ready. The download can take several minutes.
3. Click **Use a sample letter**, then **Explain this letter**.
4. Ask one of the suggested questions, then open **See exactly what the cloud received** in the privacy receipt.
5. Try **Draft a reply** and **Track this deadline**.

No login is needed. Without the on-device model the app still runs: pasted text is sent to the cloud after pattern-based redaction, and the receipt shows it.
