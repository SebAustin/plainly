import Foundation

/// Redaction is the privacy gate between a letter and the cloud.
///
/// Personal details are swapped for stable placeholders ([NAME_1], [EMAIL_1]…)
/// before any text leaves the device. The mapping (the "vault") never leaves
/// the device, so cloud answers can be rehydrated locally with `restore`.

public enum EntityType: String, Sendable, Codable, CaseIterable {
  case name = "NAME"
  case address = "ADDRESS"
  case email = "EMAIL"
  case phone = "PHONE"
  case id = "ID"
  case account = "ACCOUNT"
}

/// A personal detail found by the on-device model (names, addresses…).
public struct DetectedEntity: Sendable, Equatable {
  public let type: EntityType
  public let value: String

  public init(type: EntityType, value: String) {
    self.type = type
    self.value = value
  }
}

/// Placeholder → original value. Stays on the device.
public typealias Vault = [String: String]

public struct Redaction: Sendable, Equatable {
  public let redacted: String
  public let vault: Vault
}

private struct Match {
  let range: NSRange
  let type: EntityType
  let priority: Int
}

private let minEntityLength = 3
private let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

/// Pattern rules, in priority order: earlier rules win when spans tie.
private let patternRules: [(type: EntityType, pattern: String)] = [
  (.email, #"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#),
  (.id, #"\b\d{3}-\d{2}-\d{4}\b"#),
  (.phone, #"(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\b\d{3})[\s.-]?\d{3}[\s.-]?\d{4}\b"#),
  (.account, #"\b\d(?:[ -]?\d){7,}\b"#),
]

private let placeholderPattern = #"\[([A-Z]+)_(\d+)\]"#

private func words(of value: String) -> [String] {
  value.components(separatedBy: separators).filter { !$0.isEmpty }
}

private func findAll(
  in text: String, pattern: String, options: NSRegularExpression.Options = [],
  type: EntityType, priority: Int
) -> [Match] {
  guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
  let whole = NSRange(location: 0, length: (text as NSString).length)
  return regex.matches(in: text, range: whole).map {
    Match(range: $0.range, type: type, priority: priority)
  }
}

private func findEntityMatches(in text: String, entities: [DetectedEntity]) -> [Match] {
  entities
    .filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).count >= minEntityLength }
    .flatMap { entity -> [Match] in
      // Models tidy what they copy: line breaks become commas or spaces. Match
      // the words in order and accept any mix of whitespace and commas between.
      let escaped = words(of: entity.value).map(NSRegularExpression.escapedPattern(for:))
      guard !escaped.isEmpty else { return [] }
      // Model-found entities outrank pattern rules (priority -1).
      return findAll(
        in: text, pattern: escaped.joined(separator: #"[\s,]+"#),
        options: [.caseInsensitive], type: entity.type, priority: -1)
    }
}

private func findPatternMatches(in text: String) -> [Match] {
  patternRules.enumerated().flatMap { index, rule in
    findAll(in: text, pattern: rule.pattern, type: rule.type, priority: index)
  }
}

/// Keeps the earliest, then longest, then highest-priority match of any overlap.
private func dropOverlaps(_ matches: [Match]) -> [Match] {
  let ordered = matches.sorted { a, b in
    if a.range.location != b.range.location { return a.range.location < b.range.location }
    if a.range.length != b.range.length { return a.range.length > b.range.length }
    return a.priority < b.priority
  }
  return ordered.reduce(into: [Match]()) { kept, match in
    if let previous = kept.last, match.range.location < NSMaxRange(previous.range) { return }
    kept.append(match)
  }
}

private func valueKey(_ type: EntityType, _ value: String) -> String {
  "\(type.rawValue):\(words(of: value.lowercased()).joined(separator: " "))"
}

private struct VaultEntry {
  let placeholder: String
  let type: EntityType
  let count: Int
  let value: String
}

private func entries(of vault: Vault) -> [VaultEntry] {
  guard let regex = try? NSRegularExpression(pattern: "^\(placeholderPattern)$") else { return [] }
  return vault.compactMap { placeholder, value in
    let ns = placeholder as NSString
    guard
      let found = regex.firstMatch(in: placeholder, range: NSRange(location: 0, length: ns.length)),
      let type = EntityType(rawValue: ns.substring(with: found.range(at: 1))),
      let count = Int(ns.substring(with: found.range(at: 2)))
    else { return nil }
    return VaultEntry(placeholder: placeholder, type: type, count: count, value: value)
  }
}

/// Redacts `text`. Pass the letter's `existingVault` when redacting something
/// that belongs to the same conversation (a follow-up question), so the same
/// person keeps the same placeholder across every message the cloud sees.
public func redact(
  _ text: String, entities: [DetectedEntity] = [], existingVault: Vault = [:]
) -> Redaction {
  let known = entries(of: existingVault)
  let allEntities = entities + known.map { DetectedEntity(type: $0.type, value: $0.value) }
  let matches = dropOverlaps(
    findEntityMatches(in: text, entities: allEntities) + findPatternMatches(in: text))

  var placeholderByValue = Dictionary(
    known.map { (valueKey($0.type, $0.value), $0.placeholder) }, uniquingKeysWith: { first, _ in first })
  var countByType = known.reduce(into: [EntityType: Int]()) { counts, entry in
    counts[entry.type] = max(counts[entry.type] ?? 0, entry.count)
  }
  var vault = existingVault
  var pieces: [String] = []
  var cursor = 0
  let ns = text as NSString

  for match in matches {
    let original = ns.substring(with: match.range)
    let key = valueKey(match.type, original)
    let placeholder: String
    if let existing = placeholderByValue[key] {
      placeholder = existing
    } else {
      let count = (countByType[match.type] ?? 0) + 1
      countByType[match.type] = count
      placeholder = "[\(match.type.rawValue)_\(count)]"
      placeholderByValue[key] = placeholder
      vault[placeholder] = original
    }
    pieces.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
    pieces.append(placeholder)
    cursor = NSMaxRange(match.range)
  }
  pieces.append(ns.substring(from: cursor))

  return Redaction(redacted: pieces.joined(), vault: vault)
}

/// Puts the original values back into text that came from the cloud.
public func restore(_ text: String, vault: Vault) -> String {
  guard let regex = try? NSRegularExpression(pattern: placeholderPattern) else { return text }
  let ns = text as NSString
  var result = ""
  var cursor = 0
  for found in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
    let placeholder = ns.substring(with: found.range)
    result += ns.substring(with: NSRange(location: cursor, length: found.range.location - cursor))
    result += vault[placeholder] ?? placeholder
    cursor = NSMaxRange(found.range)
  }
  return result + ns.substring(from: cursor)
}

/// A piece of text as the privacy receipt shows it: plain text, or a
/// placeholder drawn as a black bar.
public enum ReceiptSegment: Sendable, Equatable {
  case text(String)
  case placeholder(kind: String, number: Int)
}

/// Splits text sent to the cloud into plain text and placeholders, so the
/// receipt can build its display from pieces rather than editing in place.
public func receiptSegments(_ text: String) -> [ReceiptSegment] {
  guard let regex = try? NSRegularExpression(pattern: placeholderPattern) else {
    return text.isEmpty ? [] : [.text(text)]
  }
  let ns = text as NSString
  var segments: [ReceiptSegment] = []
  var cursor = 0
  for found in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
    if found.range.location > cursor {
      segments.append(
        .text(ns.substring(with: NSRange(location: cursor, length: found.range.location - cursor))))
    }
    segments.append(
      .placeholder(
        kind: ns.substring(with: found.range(at: 1)),
        number: Int(ns.substring(with: found.range(at: 2))) ?? 0))
    cursor = NSMaxRange(found.range)
  }
  if cursor < ns.length { segments.append(.text(ns.substring(from: cursor))) }
  return segments
}
