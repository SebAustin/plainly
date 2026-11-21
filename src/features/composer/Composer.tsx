import { useRef, useState, type ChangeEvent, type DragEvent, type FormEvent } from 'react'
import type { Attachment } from '../../inference/inference'
import type { LetterInput } from '../../letters/letterService'
import { SAMPLE_LETTER } from './sampleLetter'
import './composer.css'

interface ComposerProps {
  isReading: boolean
  isDisabled: boolean
  onRead: (input: LetterInput) => void
}

interface AttachedFile {
  name: string
  attachment: Attachment
}

const ACCEPTED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
const MAX_FILE_BYTES = 10 * 1024 * 1024

function readAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result).split(',')[1] ?? '')
    reader.onerror = () => reject(new Error('Could not read that file.'))
    reader.readAsDataURL(file)
  })
}

export function Composer({ isReading, isDisabled, onRead }: ComposerProps) {
  const [text, setText] = useState('')
  const [file, setFile] = useState<AttachedFile | null>(null)
  const [fileError, setFileError] = useState<string | null>(null)
  const [isDragging, setIsDragging] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)

  async function attach(candidate: File | undefined) {
    if (!candidate) return
    if (!ACCEPTED_TYPES.includes(candidate.type)) {
      return setFileError('Use a JPEG, PNG or WebP photo, or a PDF.')
    }
    if (candidate.size > MAX_FILE_BYTES) return setFileError('That file is over 10 MB.')
    try {
      const base64 = await readAsBase64(candidate)
      setFile({ name: candidate.name, attachment: { base64, mimeType: candidate.type } })
      setFileError(null)
    } catch (error) {
      setFileError(error instanceof Error ? error.message : 'Could not read that file.')
    }
  }

  function handleDrop(event: DragEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsDragging(false)
    void attach(event.dataTransfer.files[0])
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (file) {
      const kind = file.attachment.mimeType === 'application/pdf' ? 'pdf' : 'image'
      onRead({ kind, attachment: file.attachment })
    } else if (text.trim()) {
      onRead({ kind: 'text', text: text.trim() })
    }
  }

  const hasLetter = Boolean(file) || text.trim().length > 0

  return (
    <form
      className={`sheet composer${isDragging ? ' is-dragging' : ''}`}
      onSubmit={handleSubmit}
      onDragOver={(event) => {
        event.preventDefault()
        setIsDragging(true)
      }}
      onDragLeave={() => setIsDragging(false)}
      onDrop={handleDrop}
      aria-labelledby="composer-heading"
    >
      <p className="eyebrow">Step one</p>
      <h2 id="composer-heading">The letter</h2>

      {file ? (
        <p className="composer-file">
          <span>{file.name}</span>
          <button type="button" className="link-button" onClick={() => setFile(null)}>
            Remove
          </button>
        </p>
      ) : (
        <>
          <label className="visually-hidden" htmlFor="letter-text">
            Paste the text of your letter
          </label>
          <textarea
            id="letter-text"
            value={text}
            onChange={(event: ChangeEvent<HTMLTextAreaElement>) => setText(event.target.value)}
            placeholder="Paste the letter here, or drop a photo of it."
            rows={14}
            spellCheck={false}
          />
        </>
      )}

      {fileError && (
        <p className="field-error" role="alert">
          {fileError}
        </p>
      )}

      <div className="composer-actions">
        <button type="submit" className="button-primary" disabled={!hasLetter || isReading || isDisabled}>
          {isReading ? 'Reading…' : 'Explain this letter'}
        </button>
        <input
          ref={fileInput}
          type="file"
          accept={ACCEPTED_TYPES.join(',')}
          className="visually-hidden"
          tabIndex={-1}
          aria-hidden="true"
          onChange={(event) => {
            void attach(event.target.files?.[0])
            event.target.value = ''
          }}
        />
        <button type="button" className="button-quiet" onClick={() => fileInput.current?.click()}>
          Add a photo or PDF
        </button>
        <button
          type="button"
          className="link-button"
          onClick={() => {
            setFile(null)
            setText(SAMPLE_LETTER)
          }}
        >
          Use a sample letter
        </button>
      </div>
    </form>
  )
}
