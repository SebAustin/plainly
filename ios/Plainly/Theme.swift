import SwiftUI

/// Paper, ink and postmark: the same palette as the web app, where colour
/// carries meaning (green stayed on the device, blue went to the cloud).
enum Theme {
  static let paper = Color(red: 0.965, green: 0.941, blue: 0.890)
  static let sheet = Color(red: 0.996, green: 0.990, blue: 0.972)
  static let ink = Color(red: 0.110, green: 0.122, blue: 0.170)
  static let inkSoft = Color(red: 0.345, green: 0.357, blue: 0.412)
  static let rule = Color(red: 0.836, green: 0.808, blue: 0.741)
  static let device = Color(red: 0.090, green: 0.400, blue: 0.318)
  static let cloud = Color(red: 0.137, green: 0.341, blue: 0.659)
  static let urgent = Color(red: 0.761, green: 0.255, blue: 0.165)
  static let redaction = Color(red: 0.082, green: 0.090, blue: 0.114)

  static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> ThemeFont {
    ThemeFont(size: size, weight: weight, design: .serif)
  }

  static func label(_ size: CGFloat = 11) -> ThemeFont {
    ThemeFont(size: size, weight: .medium, design: .monospaced)
  }

  static func mono(_ size: CGFloat) -> ThemeFont {
    ThemeFont(size: size, weight: .regular, design: .monospaced)
  }

  static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> ThemeFont {
    ThemeFont(size: size, weight: weight, design: .default)
  }
}

/// A font from the theme's type scale. Sizes are the design at the default
/// text size; applied with `.font(_:)` they grow with the reader's text size
/// setting, which matters for the older readers Plainly is written for.
struct ThemeFont {
  var size: CGFloat
  var weight: Font.Weight
  var design: Font.Design
  var isItalic = false

  func italic() -> ThemeFont {
    var copy = self
    copy.isItalic = true
    return copy
  }

  func weight(_ weight: Font.Weight) -> ThemeFont {
    var copy = self
    copy.weight = weight
    return copy
  }

  /// Large display type grows more slowly than body text, as Apple's styles do.
  var scalesLike: Font.TextStyle {
    switch size {
    case 28...: .largeTitle
    case 20..<28: .title3
    case 15..<20: .body
    default: .caption
    }
  }
}

private struct ScaledThemeFont: ViewModifier {
  let font: ThemeFont
  @ScaledMetric private var size: CGFloat

  init(_ font: ThemeFont) {
    self.font = font
    _size = ScaledMetric(wrappedValue: font.size, relativeTo: font.scalesLike)
  }

  func body(content: Content) -> some View {
    let base = Font.system(size: size, weight: font.weight, design: font.design)
    content.font(font.isItalic ? base.italic() : base)
  }
}

extension View {
  func font(_ font: ThemeFont) -> some View {
    modifier(ScaledThemeFont(font))
  }
}

/// A small-caps monospaced section label, like a form field heading.
struct SectionLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(Theme.label())
      .kerning(1.4)
      .foregroundStyle(Theme.inkSoft)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A sheet of paper lifted off the desk.
struct Sheet<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 3))
      .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.rule.opacity(0.7), lineWidth: 0.5))
      .shadow(color: Theme.ink.opacity(0.14), radius: 14, y: 8)
  }
}

struct InkButtonStyle: ButtonStyle {
  var filled = true
  @SwiftUI.Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Theme.text(16, weight: .semibold))
      .padding(.horizontal, 20)
      .frame(minHeight: 48)
      .foregroundStyle(filled ? Theme.sheet : Theme.ink)
      .background(filled ? Theme.ink : .clear, in: Capsule())
      .overlay(Capsule().stroke(Theme.ink, lineWidth: filled ? 0 : 1.2))
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}
