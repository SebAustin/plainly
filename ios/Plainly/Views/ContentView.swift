import PlainlyCore
import SwiftUI

struct ContentView: View {
  /// How often to look again while Apple Intelligence is still downloading.
  private static let preparingRecheck: Duration = .seconds(5)

  @Bindable var model: LetterViewModel
  // PlainlyCore has its own `Environment` (routing inputs), hence the prefix.
  @SwiftUI.Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          Masthead(model: model)
          ComposerView(model: model)

          if let error = model.errorMessage {
            Text(error)
              .font(.callout)
              .foregroundStyle(Theme.urgent)
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Theme.urgent.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
              .accessibilityLabel("Error: \(error)")
          }

          if let decoded = model.decoded {
            DecodeView(letter: decoded).id("decode")
            FollowUpView(model: model)
            ReplyView(model: model)
          }

          if !model.receipt.isEmpty {
            ReceiptView(entries: model.receipt, isDemo: model.isDemo)
          }

          Text("Plainly explains letters. It is not legal, medical or financial advice. Built with Firebase AI Logic hybrid inference.")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .alert(
        "Send without hiding names?",
        isPresented: Binding(
          get: { model.pendingConsent != nil },
          set: { if !$0 { model.declineConsent() } })
      ) {
        Button("Send to the cloud") { model.grantConsent() }
        Button("Cancel", role: .cancel) { model.declineConsent() }
      } message: {
        Text(
          "Plainly could not hide names and addresses on this device. If you continue, this letter goes to the cloud model with only email addresses and phone, ID and account numbers hidden. Your name and address will be sent."
        )
      }
      .background(Theme.paper.ignoresSafeArea())
      // The reader may have turned on Apple Intelligence in Settings meanwhile.
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { model.refreshDeviceModel() }
      }
      // Restarts whenever the status changes, and stops once it is not preparing.
      .task(id: model.deviceModel) {
        while model.deviceModel == .preparing, !Task.isCancelled {
          try? await Task.sleep(for: Self.preparingRecheck)
          model.refreshDeviceModel()
        }
      }
      .onChange(of: model.decoded != nil) { _, hasResult in
        guard hasResult else { return }
        withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo("decode", anchor: .top) }
      }
    }
  }
}

private struct Masthead: View {
  let model: LetterViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Plainly")
        .font(Theme.display(56).italic())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(.isHeader)
      Text("Official mail, in plain words. Read privately on your device.")
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
      Rectangle().fill(Theme.ink).frame(height: 2)
      VStack(alignment: .leading, spacing: 4) {
        if model.isDemo {
          // No model is involved in demo mode, so no model status is claimed.
          StatusLine(text: "Demo mode: canned answers, no model is called", isGood: false)
        } else {
          StatusLine(text: deviceText, isGood: model.deviceModel == .available)
          StatusLine(
            text: model.connectivity.isOnline ? "Cloud reachable" : "Offline",
            isGood: model.connectivity.isOnline)
        }
      }
    }
  }

  private var deviceText: String {
    switch model.deviceModel {
    case .available: "On-device model ready"
    case .preparing: "On-device model is still downloading"
    case .unavailable: "No on-device model: turn on Apple Intelligence in Settings"
    }
  }
}

private struct StatusLine: View {
  let text: String
  let isGood: Bool

  var body: some View {
    HStack(spacing: 8) {
      Circle().fill(isGood ? Theme.device : Theme.urgent).frame(width: 7, height: 7)
      Text(text).font(Theme.label(12)).foregroundStyle(Theme.ink)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A rubber stamp saying where an answer was produced.
struct SourceStamp: View {
  let source: InferenceSource
  var compact = false

  var body: some View {
    let onDevice = source == .onDevice
    VStack(spacing: 2) {
      Text(onDevice ? "ON THIS DEVICE" : "IN THE CLOUD")
        .font(Theme.label(compact ? 10 : 12).weight(.bold))
        .kerning(1.5)
      if !compact {
        Text(onDevice ? "NOTHING LEFT IT" : "DETAILS HIDDEN FIRST")
          .font(Theme.label(9))
          .kerning(1.2)
      }
    }
    .padding(.horizontal, compact ? 8 : 12)
    .padding(.vertical, compact ? 5 : 8)
    .foregroundStyle(onDevice ? Theme.device : Theme.cloud)
    .overlay(Rectangle().stroke(onDevice ? Theme.device : Theme.cloud, lineWidth: compact ? 1.2 : 2))
    .rotationEffect(.degrees(compact ? 0 : -2))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(onDevice ? "Produced on this device" : "Produced in the cloud, with your details hidden")
  }
}
