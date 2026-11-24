import Foundation
import Testing

@testable import PlainlyCore

private let ready = Environment(deviceModel: .available, isOnline: true, deviceTokenBudget: 2500)

private func environment(
  _ model: DeviceModelStatus = .available, online: Bool = true, budget: Int = 2500
) -> Environment {
  Environment(deviceModel: model, isOnline: online, deviceTokenBudget: budget)
}

@Suite struct RoutingTests {
  @Test func aLetterThatFitsIsReadOnTheDevice() {
    #expect(chooseRoute(.decode(characters: 1200), ready) == .device)
  }

  @Test func aLetterTooLongForTheDeviceGoesToTheCloudRedactedWithTheDevicesHelp() {
    #expect(chooseRoute(.decode(characters: 40_000), ready) == .cloud(redaction: .deviceAssisted))
  }

  @Test func withoutADeviceModelTheLetterGoesToTheCloudWithPatternRulesOnly() {
    #expect(
      chooseRoute(.decode(characters: 1200), environment(.unavailable)) == .cloud(redaction: .rulesOnly))
  }

  @Test func aModelThatIsStillPreparingDoesNotCountAsAvailable() {
    #expect(
      chooseRoute(.decode(characters: 1200), environment(.preparing)) == .cloud(redaction: .rulesOnly))
  }

  @Test func offlineWithoutADeviceModelIsBlocked() {
    #expect(
      chooseRoute(.decode(characters: 1200), environment(.unavailable, online: false))
        == .blocked(.offline))
  }

  @Test func offlineWithADeviceModelStillReadsTheLetter() {
    #expect(chooseRoute(.decode(characters: 1200), environment(online: false)) == .device)
  }

  @Test func findingPersonalDetailsNeverLeavesTheDevice() {
    #expect(chooseRoute(.findPersonalDetails, environment(.unavailable)) == .device)
  }

  @Test func followUpsAlwaysUseTheCloudAndAreBlockedOffline() {
    #expect(chooseRoute(.followUp, ready) == .cloud(redaction: .deviceAssisted))
    #expect(chooseRoute(.followUp, environment(online: false)) == .blocked(.offline))
  }

  @Test func draftingPrefersTheDeviceAndFallsBackByConnectivity() {
    #expect(chooseRoute(.draftReply, ready) == .either(redaction: .deviceAssisted))
    #expect(chooseRoute(.draftReply, environment(online: false)) == .device)
    #expect(chooseRoute(.draftReply, environment(.unavailable)) == .cloud(redaction: .rulesOnly))
    #expect(
      chooseRoute(.draftReply, environment(.unavailable, online: false)) == .blocked(.offline))
  }

  @Test func eachRouteMapsToOneInferenceMode() {
    #expect(Route.device.mode == .onlyOnDevice)
    #expect(Route.cloud(redaction: .rulesOnly).mode == .onlyInCloud)
    #expect(Route.either(redaction: .deviceAssisted).mode == .preferOnDevice)
    #expect(Route.blocked(.offline).mode == nil)
  }
}

private let validDecode = """
  {"sender":"Northgate Health","category":"medical","summary":"You owe money.","urgency":"high",
  "actions":[{"what":"Pay the bill","deadline":"2026-12-14"},{"what":"Call","deadline":"within 30 days"}],
  "amountDue":{"value":1284.5,"currency":"USD"},"glossary":[]}
  """

@Suite struct DecodeTests {
  @Test func parsesAValidAnswer() throws {
    let decode = try parseDecode(validDecode).get()

    #expect(decode.sender == "Northgate Health")
    #expect(decode.category == .medical)
    #expect(decode.amountDue?.value == 1284.5)
  }

  @Test func dropsADeadlineThatIsNotARealDate() throws {
    let decode = try parseDecode(validDecode).get()

    #expect(decode.actions.map(\.deadline) == ["2026-12-14", nil])
  }

  @Test func dropsADateThatDoesNotExist() throws {
    let raw = validDecode.replacingOccurrences(of: "2026-12-14", with: "2026-02-31")

    #expect(try parseDecode(raw).get().actions.first?.deadline == nil)
  }

  @Test func acceptsAnAnswerWrappedInACodeFence() throws {
    #expect(try parseDecode("```json\n\(validDecode)\n```").get().urgency == .high)
  }

  @Test func dropsMalformedGlossaryEntriesButKeepsTheRestOfTheAnswer() throws {
    let raw = validDecode.replacingOccurrences(
      of: #""glossary":[]"#,
      with: #""glossary":["collections agency",{"term":"Remit","plain":"To send payment"}]"#)

    let decode = try parseDecode(raw).get()

    #expect(decode.glossary == [Decode.GlossaryEntry(term: "Remit", plain: "To send payment")])
    #expect(decode.amountDue?.value == 1284.5)
  }

  @Test func treatsAnAmountOfZeroAsNothingOwed() throws {
    let raw = validDecode.replacingOccurrences(of: "1284.5", with: "0")

    #expect(try parseDecode(raw).get().amountDue == nil)
  }

  @Test func rejectsTextThatIsNotJSON() {
    #expect(parseDecode("I cannot help with that.") == .failure(.notJSON))
  }

  @Test func rejectsJSONOfTheWrongShape() {
    #expect(parseDecode(#"{"sender":"X","category":"spaceship"}"#) == .failure(.wrongShape))
  }

  @Test func countsWholeDaysUntilADeadline() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 23))!

    #expect(daysUntil("2026-12-14", now: now, calendar: calendar) == 23)
    #expect(daysUntil("2026-11-20", now: now, calendar: calendar) == -1)
    #expect(daysUntil("soon", now: now, calendar: calendar) == nil)
  }

  @Test func findsTheSoonestDeadline() throws {
    let raw = validDecode.replacingOccurrences(of: "within 30 days", with: "2026-12-01")

    #expect(nextDeadline(try parseDecode(raw).get()) == "2026-12-01")
  }

  @Test func personalDetailsKeepNamesAndAddressesOnly() {
    let raw = #"{"entities":[{"type":"NAME","value":"Maria Okafor"},{"type":"ORG","value":"Northgate"}]}"#

    #expect(parsePersonalDetails(raw) == [DetectedEntity(type: .name, value: "Maria Okafor")])
    #expect(parsePersonalDetails(#"{"entities":[]}"#) == [])
    // Unreadable is not the same as "none found": the caller must not trust it.
    #expect(parsePersonalDetails("nonsense") == nil)
  }
}
