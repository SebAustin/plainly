import Testing

@testable import PlainlyCore

@Suite struct RedactionTests {
  @Test func replacesEmailsPhoneNumbersAndLongAccountNumbers() {
    let letter =
      "Contact billing@northgate-health.org or call (415) 555-0134 about account 4417 1299 8830 2201."

    #expect(redact(letter).redacted == "Contact [EMAIL_1] or call [PHONE_1] about account [ACCOUNT_1].")
  }

  @Test func replacesSocialSecurityNumbers() {
    #expect(redact("SSN on file: 512-44-9087.").redacted == "SSN on file: [ID_1].")
  }

  @Test func keepsAmountsAndDatesTheCloudNeedsForDeadlines() {
    let letter = "You owe $1,284.50 by 12/14/2026. Reference year 2026."

    #expect(redact(letter).redacted == letter)
  }

  @Test func usesTheSamePlaceholderEveryTimeAValueAppears() {
    let redacted = redact("Email ana@mail.com. Again: ana@mail.com. Other: bo@mail.com.").redacted

    #expect(redacted == "Email [EMAIL_1]. Again: [EMAIL_1]. Other: [EMAIL_2].")
  }

  @Test func redactsModelFoundNamesAndAddressesCaseInsensitively() {
    let letter = "Dear Maria Okafor, we wrote to 88 Linden Ave, Apt 4. MARIA OKAFOR must reply."

    let redacted = redact(
      letter,
      entities: [
        DetectedEntity(type: .name, value: "Maria Okafor"),
        DetectedEntity(type: .address, value: "88 Linden Ave, Apt 4"),
      ]
    ).redacted

    #expect(redacted == "Dear [NAME_1], we wrote to [ADDRESS_1]. [NAME_1] must reply.")
  }

  @Test func redactsAnAddressTheModelWroteOnOneLineWhenTheLetterBreaksIt() {
    let letter = "Maria Okafor\n88 Linden Avenue, Apt 4\nOakland, CA 94607\n\nDear resident,"

    let redacted = redact(
      letter,
      entities: [DetectedEntity(type: .address, value: "88 Linden Avenue, Apt 4, Oakland, CA 94607")]
    ).redacted

    #expect(redacted == "Maria Okafor\n[ADDRESS_1]\n\nDear resident,")
  }

  @Test func ignoresEntitiesTooShortToBeSafeToReplace() {
    let redacted = redact("A notice for Al.", entities: [DetectedEntity(type: .name, value: "A")])

    #expect(redacted.redacted == "A notice for Al.")
  }

  @Test func reusesTheLettersPlaceholdersWhenRedactingAFollowUpQuestion() {
    let letter = redact(
      "Dear Maria Okafor, email ana@mail.com.",
      entities: [DetectedEntity(type: .name, value: "Maria Okafor")])

    let question = redact(
      "Can maria okafor reply from ana@mail.com or from new@mail.com?", existingVault: letter.vault)

    #expect(question.redacted == "Can [NAME_1] reply from [EMAIL_1] or from [EMAIL_2]?")
    #expect(
      question.vault == [
        "[NAME_1]": "Maria Okafor", "[EMAIL_1]": "ana@mail.com", "[EMAIL_2]": "new@mail.com",
      ])
  }

  @Test func restorePutsOriginalValuesBackIntoACloudAnswer() {
    let vault = redact(
      "Dear Maria Okafor, email ana@mail.com.",
      entities: [DetectedEntity(type: .name, value: "Maria Okafor")]
    ).vault

    let answer = restore("Yes [NAME_1], reply from [EMAIL_1] before the deadline.", vault: vault)

    #expect(answer == "Yes Maria Okafor, reply from ana@mail.com before the deadline.")
  }

  @Test func restoreLeavesUnknownPlaceholdersUntouched() {
    #expect(restore("Ask [NAME_7].", vault: [:]) == "Ask [NAME_7].")
  }
}
