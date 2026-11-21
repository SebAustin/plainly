import { describe, expect, test } from 'vitest'
import { daysUntil, parseDecode } from './decode'

const validDecode = {
  sender: 'Northgate Health',
  category: 'medical',
  summary: 'This is a bill for a clinic visit on October 3.',
  urgency: 'high',
  actions: [{ what: 'Pay the balance or call to set up a payment plan', deadline: '2026-12-14' }],
  amountDue: { value: 1284.5, currency: 'USD' },
  glossary: [{ term: 'EOB', plain: 'A summary of what your insurance paid' }],
}

describe('parseDecode', () => {
  test('accepts a well-formed decode from the model', () => {
    const result = parseDecode(JSON.stringify(validDecode))

    expect(result).toEqual({ ok: true, decode: validDecode })
  })

  test('accepts JSON wrapped in a markdown code fence', () => {
    const result = parseDecode('```json\n' + JSON.stringify(validDecode) + '\n```')

    expect(result.ok).toBe(true)
  })

  test('treats a missing deadline or amount as "none", not as an error', () => {
    const result = parseDecode(
      JSON.stringify({
        ...validDecode,
        actions: [{ what: 'Keep this letter for your records', deadline: null }],
        amountDue: null,
      }),
    )

    expect(result).toMatchObject({
      ok: true,
      decode: { amountDue: null, actions: [{ deadline: null }] },
    })
  })

  test('drops a deadline that is not a real calendar date instead of trusting it', () => {
    const result = parseDecode(
      JSON.stringify({
        ...validDecode,
        actions: [{ what: 'Reply to the office', deadline: 'within 30 days' }],
      }),
    )

    expect(result).toMatchObject({ ok: true, decode: { actions: [{ deadline: null }] } })
  })

  test('rejects output that is not JSON', () => {
    expect(parseDecode('Sure! Here is your letter explained...')).toEqual({
      ok: false,
      error: 'not-json',
    })
  })

  test('rejects JSON that is missing required fields', () => {
    expect(parseDecode(JSON.stringify({ sender: 'Northgate Health' }))).toEqual({
      ok: false,
      error: 'wrong-shape',
    })
  })
})

describe('daysUntil', () => {
  test('counts whole days from today to a deadline', () => {
    expect(daysUntil('2026-12-14', new Date('2026-11-19T18:00:00'))).toBe(25)
  })

  test('is zero on the day itself and negative once the deadline has passed', () => {
    expect(daysUntil('2026-11-19', new Date('2026-11-19T23:30:00'))).toBe(0)
    expect(daysUntil('2026-11-17', new Date('2026-11-19T08:00:00'))).toBe(-2)
  })
})
