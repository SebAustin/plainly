import type { InferenceSource } from '../../inference/inference'

interface SourceStampProps {
  source: InferenceSource
  /** Cloud calls on redacted text get a second line saying so. */
  isRedacted?: boolean
  size?: 'small' | 'large'
}

/** A postmark showing where a model call ran. */
export function SourceStamp({ source, isRedacted = false, size = 'small' }: SourceStampProps) {
  const onDevice = source === 'on_device'
  return (
    <span className={`stamp stamp-${size} ${onDevice ? 'stamp-device' : 'stamp-cloud'}`}>
      <span>{onDevice ? 'On this device' : 'In the cloud'}</span>
      {size === 'large' && (
        <small>{onDevice ? 'Nothing left it' : isRedacted ? 'Personal details hidden' : 'Sent with your consent'}</small>
      )}
    </span>
  )
}
