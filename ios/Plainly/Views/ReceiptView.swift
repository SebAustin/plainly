import PlainlyCore
import SwiftUI

/// The privacy receipt: every model call for this letter, where it ran and,
/// for cloud calls, the exact text that was sent.
struct ReceiptView: View {
  let entries: [ReceiptEntry]
  let isDemo: Bool
  @State private var expanded: Set<UUID> = []

  var body: some View {
    Sheet {
      VStack(alignment: .leading, spacing: 12) {
        SectionLabel(text: "Privacy receipt")
        Text(summary).font(Theme.label(13)).foregroundStyle(Theme.ink)
        if isDemo {
          Text("Demo mode: these calls were simulated.").font(.footnote).foregroundStyle(Theme.urgent)
        }
        Rectangle()
          .stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
          .foregroundStyle(Theme.rule)
          .frame(height: 1)

        ForEach(entries) { entry in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(entry.task.rawValue).font(Theme.label(13)).foregroundStyle(Theme.ink)
              Spacer()
              SourceStamp(source: entry.source, compact: true)
            }
            if let sent = entry.sentToCloud {
              Button {
                if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
              } label: {
                Label(
                  "See exactly what the cloud received",
                  systemImage: expanded.contains(entry.id) ? "chevron.down" : "chevron.right"
                )
                .font(Theme.label(12))
                .underline()
                .foregroundStyle(Theme.cloud)
                .frame(minHeight: 44, alignment: .leading)
              }
              .buttonStyle(.plain)
              if expanded.contains(entry.id) {
                Text(blackedOut(sent))
                  .font(.system(size: 12, design: .monospaced))
                  .lineSpacing(4)
                  .padding(12)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(Theme.paper)
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
    }
  }

  private var summary: String {
    let cloud = entries.filter { $0.source == .inCloud }.count
    let calls = entries.count == 1 ? "1 model call" : "\(entries.count) model calls"
    return "\(calls) · \(cloud) left this device"
  }

  /// Shows placeholders such as [NAME_1] as black redaction bars.
  private func blackedOut(_ text: String) -> AttributedString {
    var styled = AttributedString(text)
    styled.foregroundColor = Theme.ink
    let pattern = /\[([A-Z]+)_(\d+)\]/
    for match in text.matches(of: pattern) {
      guard let range = Range(match.range, in: styled) else { continue }
      var bar = AttributedString(" \(match.output.1) \(match.output.2) ")
      bar.backgroundColor = Theme.redaction
      bar.foregroundColor = Theme.sheet
      styled.replaceSubrange(range, with: bar)
    }
    return styled
  }
}
