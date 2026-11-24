import Foundation

/// A Decode is the plain-language reading of one letter: what it is, what the
/// reader has to do, by when, and how much it costs. Whatever a model returns
/// is validated here before the UI trusts it.

public enum LetterCategory: String, Sendable, Codable, CaseIterable {
  case bill, medical, tax, immigration, benefits, legal, housing, other
}

public enum Urgency: String, Sendable, Codable, CaseIterable {
  case low, medium, high
}

public struct Decode: Sendable, Equatable, Codable {
  public struct Action: Sendable, Equatable, Codable {
    public var what: String
    /// YYYY-MM-DD, or nil if the letter gives none.
    public var deadline: String?
  }

  public struct Amount: Sendable, Equatable, Codable {
    public var value: Double
    public var currency: String
  }

  public struct GlossaryEntry: Sendable, Equatable, Codable {
    public var term: String
    public var plain: String
  }

  public var sender: String
  public var category: LetterCategory
  public var summary: String
  public var urgency: Urgency
  public var actions: [Action]
  public var amountDue: Amount?
  public var glossary: [GlossaryEntry]

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sender = try container.decode(String.self, forKey: .sender)
    category = try container.decode(LetterCategory.self, forKey: .category)
    summary = try container.decode(String.self, forKey: .summary)
    urgency = try container.decode(Urgency.self, forKey: .urgency)
    actions = try container.decode([Action].self, forKey: .actions)
    amountDue = try container.decodeIfPresent(Amount.self, forKey: .amountDue)
    // The glossary is a nicety. A malformed entry is dropped; it must never
    // cost the reader the deadline and the amount.
    let entries = try container.decodeIfPresent([Lossy<GlossaryEntry>].self, forKey: .glossary)
    glossary = (entries ?? []).compactMap(\.value)
  }
}

/// Decodes to nil instead of failing when one array element has the wrong shape.
private struct Lossy<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: Decoder) throws {
    value = try? decoder.singleValueContainer().decode(Value.self)
  }
}

public enum DecodeParseError: Error, Equatable {
  case notJSON
  case wrongShape
}

private let maxGlossaryEntries = 4

/// Strips a Markdown code fence and anything around the outermost JSON object.
func extractJSON(_ raw: String) -> Data? {
  guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
    return nil
  }
  return String(raw[start...end]).data(using: .utf8)
}

private func calendarDate(_ iso: String, calendar: Calendar) -> Date? {
  let parts = iso.split(separator: "-").compactMap { Int($0) }
  guard iso.count == 10, parts.count == 3 else { return nil }
  let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
  // `date(from:)` rolls 2026-02-31 over to March, so check it round-trips.
  guard let date = calendar.date(from: components),
    calendar.dateComponents([.year, .month, .day], from: date) == components
  else { return nil }
  return date
}

public func parseDecode(_ raw: String) -> Result<Decode, DecodeParseError> {
  guard let data = extractJSON(raw),
    (try? JSONSerialization.jsonObject(with: data)) != nil
  else { return .failure(.notJSON) }
  guard var decode = try? JSONDecoder().decode(Decode.self, from: data) else {
    return .failure(.wrongShape)
  }

  // A model may write "within 30 days" where a date belongs. An invented
  // deadline is worse than none, so anything that is not a real date is dropped.
  let calendar = Calendar(identifier: .gregorian)
  decode.actions = decode.actions.map { action in
    let isReal = action.deadline.flatMap { calendarDate($0, calendar: calendar) } != nil
    return Decode.Action(what: action.what, deadline: isReal ? action.deadline : nil)
  }
  decode.glossary = Array(decode.glossary.prefix(maxGlossaryEntries))
  // A model asked to fill in an amount writes 0 when nothing is owed.
  if let amount = decode.amountDue, amount.value <= 0 { decode.amountDue = nil }
  return .success(decode)
}

/// Whole calendar days from `now` to an ISO deadline. Negative once it has passed.
public func daysUntil(_ isoDate: String, now: Date = Date(), calendar: Calendar = .current) -> Int? {
  guard let deadline = calendarDate(isoDate, calendar: calendar) else { return nil }
  let today = calendar.startOfDay(for: now)
  return calendar.dateComponents([.day], from: today, to: deadline).day
}

/// The soonest deadline across all actions, or nil if the letter has none.
public func nextDeadline(_ decode: Decode) -> String? {
  decode.actions.compactMap(\.deadline).min()
}

// MARK: - Personal details

private struct PersonalDetails: Codable {
  struct Entity: Codable {
    let type: String
    let value: String
  }
  let entities: [Entity]
}

/// Returns the entities the model found, or nil when its answer could not be
/// read. Nil is not "nobody is named": the caller must not treat the text as
/// cleaned of names and addresses.
public func parsePersonalDetails(_ raw: String) -> [DetectedEntity]? {
  guard let data = extractJSON(raw),
    let details = try? JSONDecoder().decode(PersonalDetails.self, from: data)
  else { return nil }
  return details.entities.compactMap { entity in
    guard let type = EntityType(rawValue: entity.type), type == .name || type == .address else {
      return nil
    }
    return DetectedEntity(type: type, value: entity.value)
  }
}
