import { describe, expect, test } from 'vitest'
import { parsePersonalDetails } from './personalDetails'

describe('parsePersonalDetails', () => {
  test('returns the names and addresses the model listed', () => {
    const raw = '{"entities":[{"type":"NAME","value":"Maria Okafor"}]}'

    expect(parsePersonalDetails(raw)).toEqual([{ type: 'NAME', value: 'Maria Okafor' }])
  })

  test('treats an empty list as "nobody is named"', () => {
    expect(parsePersonalDetails('{"entities":[]}')).toEqual([])
  })

  test('returns null for an answer it cannot read, which is not the same as "none found"', () => {
    expect(parsePersonalDetails('Here are the names: Maria Okafor')).toBeNull()
    expect(parsePersonalDetails('{"entities":"Maria"}')).toBeNull()
  })
})
