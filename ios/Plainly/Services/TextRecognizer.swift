import ImageIO
import UIKit
import Vision

/// Reads the text of a photographed letter on the device with Vision.
/// The on-device language model is text-only, so this is what keeps a photo's
/// pixels local: only the recognised text moves on, and only after redaction.
enum TextRecognizer {
  enum Failure: Error { case unreadableImage }

  static func recognizeText(in imageData: Data) async throws -> String {
    guard let photo = UIImage(data: imageData), let image = photo.cgImage else {
      throw Failure.unreadableImage
    }
    // iPhone photos are stored in sensor orientation with a rotation flag.
    // Vision reads the raw pixels, so it has to be told which way is up.
    let orientation = CGImagePropertyOrientation(photo.imageOrientation)
    return try await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
      let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
      return lines.joined(separator: "\n")
    }.value
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
