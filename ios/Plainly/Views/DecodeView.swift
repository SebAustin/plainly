import PlainlyCore
import SwiftUI

struct DecodeView: View {
  let letter: DecodedLetter

  private var decode: Decode { letter.decode }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 10) {
        SectionLabel(text: "\(decode.category.rawValue) · \(decode.urgency.rawValue) urgency")
        Text(decode.sender.uppercased())
          .font(Theme.display(30, weight: .semibold))
          .foregroundStyle(Theme.ink)
        SourceStamp(source: letter.source)
      }

      Text(decode.summary)
        .font(Theme.display(21, weight: .regular))
        .lineSpacing(4)
        .foregroundStyle(Theme.ink)

      figures

      if !decode.actions.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          SectionLabel(text: "What you need to do")
          ForEach(Array(decode.actions.enumerated()), id: \.offset) { _, action in
            ActionRow(action: action)
          }
        }
      }

      if !decode.glossary.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          SectionLabel(text: "Words they used")
          ForEach(Array(decode.glossary.enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.term).font(Theme.display(17).italic()).foregroundStyle(Theme.ink)
              Text(entry.plain).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var figures: some View {
    let deadline = nextDeadline(decode)
    if deadline != nil || decode.amountDue != nil {
      VStack(alignment: .leading, spacing: 0) {
        Rectangle().fill(Theme.ink).frame(height: 1.5)
        HStack(alignment: .top, spacing: 24) {
          if let deadline, let days = daysUntil(deadline) {
            Figure(
              value: "\(abs(days))", label: days >= 0 ? "Days left" : "Days overdue",
              detail: formatted(deadline), isUrgent: days <= 7)
          }
          if let amount = decode.amountDue {
            Figure(
              value: amount.value.formatted(.currency(code: amount.currency)), label: "You owe",
              detail: nil, isUrgent: false)
          }
        }
        .padding(.vertical, 14)
        Rectangle().fill(Theme.rule).frame(height: 1)
      }
    }
  }

  /// Parsed as Gregorian, then shown in the phone's own calendar and language.
  private func formatted(_ isoDate: String) -> String {
    deadlineDate(isoDate)?.formatted(date: .complete, time: .omitted) ?? isoDate
  }
}

private struct Figure: View {
  let value: String
  let label: String
  let detail: String?
  let isUrgent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(Theme.display(46, weight: .semibold))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .foregroundStyle(isUrgent ? Theme.urgent : Theme.ink)
      Text(label.uppercased()).font(Theme.label()).kerning(1.2).foregroundStyle(Theme.inkSoft)
      if let detail { Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft) }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ActionRow: View {
  let action: Decode.Action
  @State private var isDone = false

  var body: some View {
    Button {
      isDone.toggle()
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isDone ? "checkmark.square.fill" : "square")
          .font(Theme.text(20))
          .foregroundStyle(Theme.ink)
        VStack(alignment: .leading, spacing: 2) {
          Text(action.what).strikethrough(isDone).foregroundStyle(Theme.ink)
          if let deadline = action.deadline {
            Text("By \(deadline)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.urgent)
          }
        }
        .multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isDone ? .isSelected : [])
  }
}
