import PlainlyCore
import SwiftUI

struct FollowUpView: View {
  @Bindable var model: LetterViewModel

  private let suggestions = [
    "What happens if I miss the deadline?", "Who do I call, and what do I say?",
    "Can I ask for more time?",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Rectangle().fill(Theme.ink).frame(height: 1.5)
      SectionLabel(text: "Ask about this letter")
      Text(notice).font(.footnote).foregroundStyle(Theme.inkSoft)

      ForEach(model.exchanges) { exchange in
        VStack(alignment: .leading, spacing: 8) {
          Text(exchange.question)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
          HStack(alignment: .firstTextBaseline) {
            SectionLabel(text: "Plainly")
            Spacer()
            SourceStamp(source: .inCloud, compact: true)
          }
          Text(exchange.answer).font(Theme.display(18, weight: .regular)).lineSpacing(3)
            .foregroundStyle(Theme.ink)
        }
      }

      if model.exchanges.isEmpty {
        ForEach(suggestions, id: \.self) { suggestion in
          Button(suggestion) { Task { await model.ask(suggestion) } }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
            .disabled(model.isAsking)
        }
      }

      HStack(spacing: 10) {
        TextField("Ask anything about this letter", text: $model.question, axis: .vertical)
          .lineLimit(1...3)
          .submitLabel(.send)
          .onSubmit { Task { await model.ask() } }
          .padding(.vertical, 10)
          .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }
        Button {
          Task { await model.ask() }
        } label: {
          if model.isAsking { ProgressView().tint(Theme.sheet) } else { Text("Ask") }
        }
        .buttonStyle(InkButtonStyle())
        .disabled(model.isAsking || model.question.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }

  private var notice: String {
    switch model.redactionLevel {
    case .deviceAssisted:
      "Questions go to the cloud model. Names, addresses and account numbers are hidden first, then put back in the answer on this device."
    case .rulesOnly:
      "Questions go to the cloud model. Without an on-device model only emails, phone, ID and account numbers are hidden: names and addresses are not."
    }
  }
}

struct ReplyView: View {
  @Bindable var model: LetterViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Rectangle().fill(Theme.ink).frame(height: 1.5)
      SectionLabel(text: "Write back")
      Text("What should the reply ask for?").font(.footnote).foregroundStyle(Theme.inkSoft)
      TextField("Goal of the reply", text: $model.replyGoal, axis: .vertical)
        .lineLimit(1...3)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }
      Button {
        Task { await model.writeReply() }
      } label: {
        if model.isDrafting {
          HStack(spacing: 8) { ProgressView(); Text("Drafting…") }
        } else {
          Text("Draft a reply")
        }
      }
      .buttonStyle(InkButtonStyle(filled: false))
      .disabled(model.isDrafting)

      if let draft = model.draft {
        Sheet {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              SectionLabel(text: "Your draft")
              Spacer()
              SourceStamp(source: draft.source, compact: true)
            }
            Text(draft.text)
              .font(Theme.display(16, weight: .regular))
              .lineSpacing(4)
              .foregroundStyle(Theme.ink)
              .textSelection(.enabled)
            ShareLink("Share or copy", item: draft.text)
              .font(.subheadline)
              .foregroundStyle(Theme.ink)
              .frame(minHeight: 44)
          }
        }
      }
    }
  }
}
