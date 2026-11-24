# Plainly for iOS

The same privacy gate as the web app, using Firebase AI Logic hybrid inference
with Apple Foundation Models on the device and Gemini in the cloud.

| Task | Model given to the session | Why |
| --- | --- | --- |
| Read the letter | system model only | The raw letter stays on the device. |
| Find names and addresses | system model only | So they can be hidden before any cloud call. |
| Answer follow-up questions | Gemini only | The cloud receives redacted text only. |
| Draft a reply | hybrid, system model first | It works on already-redacted text. |

A photographed letter is turned into text on the device with Vision, because
the on-device model is text-only. The picture is never uploaded.

## Layout

- `PlainlyCore/`: redaction, routing and parsing as a pure Swift package. Run `swift test` there.
- `Plainly/`: the SwiftUI app. `Services/FirebaseInference.swift` is the only file that calls Firebase AI Logic.
- `project.yml`: the XcodeGen spec. Run `xcodegen generate` after changing it.

## Run it

1. Open `Plainly.xcodeproj` in Xcode 26.2 or newer and run on an iOS 26+ simulator or device.
2. Without `GoogleService-Info.plist` the app runs in demo mode with canned answers, and says so.
3. For real models: register an iOS app with bundle ID `com.sebaustin.plainly` in the Firebase
   project, put its `GoogleService-Info.plist` in this folder (it is git-ignored), run once, and
   register the App Check debug token printed in the Xcode console.
4. On-device inference needs Apple Intelligence turned on. Without it, names and addresses
   cannot be found, so the app asks before anything is sent: if you agree, the letter goes to the
   cloud with only emails and phone, ID and account numbers hidden. The same question is asked if
   the on-device model's list of names comes back unreadable.
5. To try that path on a Mac that has Apple Intelligence, launch a Debug build with the argument
   `-simulateNoAppleIntelligence`.
