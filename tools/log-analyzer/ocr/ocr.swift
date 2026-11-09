// The text of a screenshot, with the Vision framework of macOS (offline, built in): one line of the picture per line on
// stdout, top to bottom. Compiled once by ocr.py (swiftc -O) into ~/.cache/playground: running it as a script costs about
// a minute of compilation each time.
//
//   ocr <image>     exit 0: text printed (maybe none), 1: the image cannot be read
//
// Language correction is off: it "corrects" class names and keys (org.apache.kafka, max.poll.interval.ms). The pieces
// of text Vision returns on the same row of the picture (a log line split by a highlight, the cells of a table) are
// joined, left to right.
import AppKit
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: ocr <image>") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("cannot read the image \(url.path)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
do {
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
} catch {
    fail("text recognition failed: \(error.localizedDescription)")
}

struct Piece {
    let text: String
    let box: CGRect
}
// Vision boxes are normalized, origin at the bottom left: top to bottom is the decreasing midY
let pieces = (request.results ?? []).compactMap { observation -> Piece? in
    guard let text = observation.topCandidates(1).first?.string else { return nil }
    return Piece(text: text, box: observation.boundingBox)
}.sorted { $0.box.midY > $1.box.midY }

// a piece belongs to the current row when its middle is within half the height of the row's first piece
var rows: [[Piece]] = []
for piece in pieces {
    if let first = rows.last?.first, abs(first.box.midY - piece.box.midY) < first.box.height / 2 {
        rows[rows.count - 1].append(piece)
    } else {
        rows.append([piece])
    }
}
for row in rows {
    print(row.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: " "))
}
