const PLACEHOLDER = /(\[[A-Z]+_\d+\])/

/** Renders redacted text with each placeholder shown as a blacked-out bar. */
export function RedactedText({ text }: { text: string }) {
  return (
    <>
      {text.split(PLACEHOLDER).map((piece, index) =>
        PLACEHOLDER.test(piece) ? (
          <mark key={index} className="redaction" title="Hidden from the cloud">
            {piece.slice(1, -1).replace('_', ' ')}
          </mark>
        ) : (
          piece
        ),
      )}
    </>
  )
}
