import Foundation
import FoundationModels

/// The answer shapes, in the two forms the models need them.
///
/// Cloud calls send the `@Generable` schema as the structured-output constraint.
///
/// On-device calls cannot: Apple applies its default content guardrails to
/// schema-guided generation, and those reject ordinary medical and legal
/// letters ("may contain sensitive content"). The permissive guardrails that
/// suit explaining a user's own letter only apply to plain-text generation.
/// So on the device the model fills in a JSON template instead.
///
/// Either way the result is JSON text that PlainlyCore's parsers validate
/// before the interface uses anything.

enum JSONTemplate {
  private static let rules =
    "Answer with one JSON object only, no Markdown and no other text. "
    + "Copy this template and replace every <...> with content from the letter. "
    + "Keep the double quotes around text values."

  static let decode = """
    \(rules)
    {"sender": "<who sent the letter>", \
    "category": "<one of: bill, medical, tax, immigration, benefits, legal, housing, other>", \
    "summary": "<two or three short sentences saying what this letter is>", \
    "urgency": "<low, medium or high; high if money, rights or benefits are lost by not acting>", \
    "actions": [{"what": "<one thing the reader must do, starting with a verb>", \
    "deadline": "<the due date for it as YYYY-MM-DD, or none>"}], \
    "amountDue": {"value": <amount owed as a number, 0 if nothing is owed>, "currency": "<currency code such as USD>"}, \
    "glossary": [{"term": "<a jargon word from the letter>", "plain": "<what it means in plain words>"}]}
    """

  static let personalDetails = """
    \(rules)
    {"entities": [{"type": "<NAME or ADDRESS>", "value": "<the exact text as it appears>"}]}
    """
}

@Generable
enum GeneratedCategory: String, Encodable {
  case bill, medical, tax, immigration, benefits, legal, housing, other
}

@Generable
enum GeneratedUrgency: String, Encodable {
  case low, medium, high
}

@Generable
struct GeneratedAction: Encodable {
  @Guide(description: "One thing the reader must do, starting with a verb")
  var what: String
  @Guide(description: "The due date for this action as YYYY-MM-DD, taken from the letter. Leave empty only if the letter gives no date")
  var deadline: String?
}

@Generable
struct GeneratedAmount: Encodable {
  var value: Double
  @Guide(description: "ISO 4217 currency code, for example USD")
  var currency: String
}

@Generable
struct GeneratedTerm: Encodable {
  @Guide(description: "A jargon word or phrase copied from the letter")
  var term: String
  @Guide(description: "What it means, in plain words")
  var plain: String
}

@Generable
struct GeneratedDecode: Encodable {
  @Guide(description: "Who sent the letter: the organisation or office")
  var sender: String
  var category: GeneratedCategory
  @Guide(description: "Two or three short sentences, at a 12-year-old reading level, saying what this letter is. Only facts from the letter")
  var summary: String
  @Guide(description: "high if money, rights or benefits are lost by not acting")
  var urgency: GeneratedUrgency
  @Guide(description: "Everything the reader must do, most important first, such as paying an amount by a date")
  var actions: [GeneratedAction]
  @Guide(description: "Money the reader owes, if any")
  var amountDue: GeneratedAmount?
  @Guide(description: "Jargon terms from the letter, explained in plain words", .maximumCount(4))
  var glossary: [GeneratedTerm]
}

@Generable
enum GeneratedEntityType: String, Encodable {
  case name = "NAME"
  case address = "ADDRESS"
}

@Generable
struct GeneratedEntity: Encodable {
  var type: GeneratedEntityType
  @Guide(description: "The exact text as it appears in the letter")
  var value: String
}

@Generable
struct GeneratedPersonalDetails: Encodable {
  @Guide(description: "Every person name and postal address in the text. Not organisations")
  var entities: [GeneratedEntity]
}

func jsonText(_ value: some Encodable) throws -> String {
  String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}
