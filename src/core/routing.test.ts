import { describe, expect, test } from 'vitest'
import { chooseRoute, type Environment } from './routing'

const ready: Environment = {
  deviceModel: 'available',
  isOnline: true,
  hasCloudConsent: false,
  deviceTokenBudget: 6000,
}

const without = (overrides: Partial<Environment>): Environment => ({ ...ready, ...overrides })

describe('chooseRoute: decoding a letter', () => {
  test('a short pasted letter is decoded strictly on device', () => {
    const route = chooseRoute({ kind: 'decode', input: { kind: 'text', characters: 2000 } }, ready)

    expect(route).toEqual({ run: 'device', mode: 'only_on_device' })
  })

  test('a photo of a letter is decoded strictly on device', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'image', mimeType: 'image/jpeg' } },
      ready,
    )

    expect(route).toEqual({ run: 'device', mode: 'only_on_device' })
  })

  test('a short letter still works offline', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'text', characters: 2000 } },
      without({ isOnline: false }),
    )

    expect(route).toEqual({ run: 'device', mode: 'only_on_device' })
  })

  test('a letter too long for the device goes to the cloud, redacted first', () => {
    // 40,000 characters ≈ 10,000 tokens, over the 6,000 token budget.
    const route = chooseRoute({ kind: 'decode', input: { kind: 'text', characters: 40_000 } }, ready)

    expect(route).toEqual({ run: 'cloud', mode: 'only_in_cloud', redaction: 'device-assisted' })
  })

  test('without a device model, text goes to the cloud with rule-based redaction only', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'text', characters: 2000 } },
      without({ deviceModel: 'unavailable' }),
    )

    expect(route).toEqual({ run: 'cloud', mode: 'only_in_cloud', redaction: 'rules-only' })
  })

  test('a PDF cannot be redacted, so it needs explicit consent before the cloud sees it', () => {
    const task = { kind: 'decode', input: { kind: 'pdf' } } as const

    expect(chooseRoute(task, ready)).toEqual({ run: 'blocked', reason: 'needs-cloud-consent' })
    expect(chooseRoute(task, without({ hasCloudConsent: true }))).toEqual({
      run: 'cloud',
      mode: 'only_in_cloud',
      redaction: 'none',
    })
  })

  test('a photo with no device model needs consent, because images cannot be redacted', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'image', mimeType: 'image/png' } },
      without({ deviceModel: 'unavailable' }),
    )

    expect(route).toEqual({ run: 'blocked', reason: 'needs-cloud-consent' })
  })

  test('an image format the device cannot read is treated like any other cloud-only file', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'image', mimeType: 'image/webp' } },
      ready,
    )

    expect(route).toEqual({ run: 'blocked', reason: 'needs-cloud-consent' })
  })

  test('offline with no device model, nothing can run', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'text', characters: 2000 } },
      without({ deviceModel: 'unavailable', isOnline: false }),
    )

    expect(route).toEqual({ run: 'blocked', reason: 'offline' })
  })

  test('while the device model is still downloading, decoding waits for it rather than leaking', () => {
    const route = chooseRoute(
      { kind: 'decode', input: { kind: 'text', characters: 2000 } },
      without({ deviceModel: 'downloading' }),
    )

    expect(route).toEqual({ run: 'device', mode: 'only_on_device' })
  })
})

describe('chooseRoute: after decoding', () => {
  test('finding personal details runs strictly on device', () => {
    expect(chooseRoute({ kind: 'find-personal-details', characters: 2000 }, ready)).toEqual({
      run: 'device',
      mode: 'only_on_device',
    })
  })

  test('follow-up conversation is multi-turn, so it runs in the cloud on redacted text', () => {
    expect(chooseRoute({ kind: 'follow-up' }, ready)).toEqual({
      run: 'cloud',
      mode: 'only_in_cloud',
      redaction: 'device-assisted',
    })
  })

  test('follow-up is unavailable offline', () => {
    expect(chooseRoute({ kind: 'follow-up' }, without({ isOnline: false }))).toEqual({
      run: 'blocked',
      reason: 'offline',
    })
  })

  test('drafting a reply works on already-redacted text, so either side may answer', () => {
    expect(chooseRoute({ kind: 'draft-reply' }, ready)).toEqual({
      run: 'either',
      mode: 'prefer_on_device',
      redaction: 'device-assisted',
    })
  })

  test('drafting a reply offline stays on device', () => {
    expect(chooseRoute({ kind: 'draft-reply' }, without({ isOnline: false }))).toEqual({
      run: 'device',
      mode: 'only_on_device',
    })
  })
})
