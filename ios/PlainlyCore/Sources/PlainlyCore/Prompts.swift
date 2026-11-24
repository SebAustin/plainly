import Foundation

/// Prompts shared by the on-device and cloud models.
enum Prompts {
  static let decoderSystem = [
    "You explain official letters (bills, medical, tax, immigration, benefits, legal, housing) to people who find them confusing.",
    "Write at a 12-year-old reading level. Short sentences. No jargon.",
    "Only state what the letter says. Never invent a deadline, an amount or a requirement.",
    "Text like [NAME_1] or [ACCOUNT_2] is a privacy placeholder: copy it exactly, never guess what it stands for.",
    "List every action the letter asks for, and give the due date of each one when the letter states it.",
  ].joined(separator: " ")

  static func decode(letter: String) -> String {
    "Explain this letter.\n\n<letter>\n\(letter)\n</letter>"
  }

  static let personalDetailsSystem = [
    "You find personal details in letters so they can be hidden.",
    "List every person name and every postal address, copied exactly as written.",
    "Do not list organisations, offices or companies.",
  ].joined(separator: " ")

  static func personalDetails(text: String) -> String {
    "List the person names and postal addresses in this text.\n\n<text>\n\(text)\n</text>"
  }

  static func followUpSystem(redactedLetter: String) -> String {
    [
      "You help someone understand and respond to an official letter. Be brief, concrete and kind.",
      "Write at a 12-year-old reading level. If the letter does not answer the question, say so and suggest who to ask.",
      "Answer in plain text only: no Markdown, no asterisks, no headings.",
      "You are not a lawyer or a doctor: for decisions with legal or medical consequences, say they should confirm with the sender or a professional.",
      "Text like [NAME_1] is a privacy placeholder for a detail hidden from you. Use the placeholder as-is; never ask for or guess the real value.",
      "\n<letter>\n\(redactedLetter)\n</letter>",
    ].joined(separator: " ")
  }

  static let draftReplySystem = [
    "You draft short, polite, plain-language replies to official letters.",
    "Keep placeholders like [NAME_1] exactly as written. Use [YOUR REQUEST] where the writer must fill something in.",
    "Output only the reply text.",
  ].joined(separator: " ")

  static func draftReply(redactedLetter: String, goal: String) -> String {
    "Draft a reply to this letter. Goal of the reply: \(goal)\n\n<letter>\n\(redactedLetter)\n</letter>"
  }
}

/// A fictional medical bill, for trying the app without a real letter.
public let sampleLetter = """
  NORTHGATE COMMUNITY HEALTH
  Patient Financial Services

  November 12, 2026

  Maria Okafor
  88 Linden Avenue, Apt 4
  Oakland, CA 94607

  Account number: 4417 1299 8830 2201

  Dear Maria Okafor,

  This statement reflects charges for services rendered on 10/03/2026. Following adjudication by your insurance carrier, the remaining patient responsibility is $1,284.50.

  Payment in full is due on or before December 14, 2026. Accounts with an unpaid balance after this date may be referred to an outside collections agency without further notice.

  If you are unable to remit payment in full, you may be eligible for a monthly payment arrangement or for our Financial Assistance Program. To inquire, contact Patient Financial Services at (415) 555-0134 or billing@northgate-health.org prior to the due date.

  Sincerely,
  Patient Financial Services
  """
