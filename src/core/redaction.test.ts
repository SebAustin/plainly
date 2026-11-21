import { describe, expect, test } from 'vitest'
import { redact, restore } from './redaction'

describe('redact', () => {
  test('replaces emails, phone numbers and long account numbers with placeholders', () => {
    const letter =
      'Contact billing@northgate-health.org or call (415) 555-0134 about account 4417 1299 8830 2201.'

    const { redacted } = redact(letter)

    expect(redacted).toBe(
      'Contact [EMAIL_1] or call [PHONE_1] about account [ACCOUNT_1].',
    )
  })

  test('replaces US social security numbers', () => {
    const { redacted } = redact('SSN on file: 512-44-9087.')

    expect(redacted).toBe('SSN on file: [ID_1].')
  })

  test('keeps amounts and dates, which the cloud needs to reason about deadlines', () => {
    const letter = 'You owe $1,284.50 by 12/14/2026. Reference year 2026.'

    const { redacted } = redact(letter)

    expect(redacted).toBe(letter)
  })

  test('uses the same placeholder every time the same value appears', () => {
    const { redacted } = redact('Email ana@mail.com. Again: ana@mail.com. Other: bo@mail.com.')

    expect(redacted).toBe('Email [EMAIL_1]. Again: [EMAIL_1]. Other: [EMAIL_2].')
  })

  test('redacts names and addresses found by the on-device model, case-insensitively', () => {
    const letter = 'Dear Maria Okafor, we wrote to 88 Linden Ave, Apt 4. MARIA OKAFOR must reply.'

    const { redacted } = redact(letter, [
      { type: 'NAME', value: 'Maria Okafor' },
      { type: 'ADDRESS', value: '88 Linden Ave, Apt 4' },
    ])

    expect(redacted).toBe('Dear [NAME_1], we wrote to [ADDRESS_1]. [NAME_1] must reply.')
  })

  test('redacts an address the model wrote on one line when the letter breaks it across lines', () => {
    const letter = 'Maria Okafor\n88 Linden Avenue, Apt 4\nOakland, CA 94607\n\nDear resident,'

    const { redacted } = redact(letter, [
      { type: 'ADDRESS', value: '88 Linden Avenue, Apt 4, Oakland, CA 94607' },
    ])

    expect(redacted).toBe('Maria Okafor\n[ADDRESS_1]\n\nDear resident,')
  })

  test('ignores model-found entities too short to be safe to replace', () => {
    const { redacted } = redact('A notice for Al.', [{ type: 'NAME', value: 'A' }])

    expect(redacted).toBe('A notice for Al.')
  })
})

describe('redact with an existing vault', () => {
  test('reuses placeholders from the letter when redacting a follow-up question', () => {
    const letter = redact('Dear Maria Okafor, email ana@mail.com.', [
      { type: 'NAME', value: 'Maria Okafor' },
    ])

    const question = redact(
      'Can maria okafor reply from ana@mail.com or from new@mail.com?',
      [],
      letter.vault,
    )

    expect(question.redacted).toBe('Can [NAME_1] reply from [EMAIL_1] or from [EMAIL_2]?')
    expect(question.vault).toEqual({
      '[NAME_1]': 'Maria Okafor',
      '[EMAIL_1]': 'ana@mail.com',
      '[EMAIL_2]': 'new@mail.com',
    })
  })
})

describe('restore', () => {
  test('puts the original values back into a cloud answer', () => {
    const { vault } = redact('Dear Maria Okafor, email ana@mail.com.', [
      { type: 'NAME', value: 'Maria Okafor' },
    ])

    const answer = restore('Yes [NAME_1], reply from [EMAIL_1] before the deadline.', vault)

    expect(answer).toBe('Yes Maria Okafor, reply from ana@mail.com before the deadline.')
  })

  test('leaves unknown placeholders untouched', () => {
    expect(restore('Ask [NAME_7].', {})).toBe('Ask [NAME_7].')
  })
})
