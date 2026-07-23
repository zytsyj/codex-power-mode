import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct DemoFrame {
    let filename: String
    let delay: Double
}

private let demos: [(filename: String, frames: [DemoFrame])] = [
    (
        "focus-demo.gif",
        [
            DemoFrame(filename: "matrix-focus-dark-observe-90.png", delay: 0.75),
            DemoFrame(filename: "matrix-focus-dark-act-580.png", delay: 0.8),
            DemoFrame(filename: "matrix-focus-dark-verify-580.png", delay: 0.85),
            DemoFrame(filename: "complete-focus-dark-verified.png", delay: 1.15)
        ]
    ),
    (
        "arcade-demo.gif",
        [
            DemoFrame(filename: "cursor-arcade-dark-neon-milestone.png", delay: 0.45),
            DemoFrame(filename: "typing-arcade-dark-gold.png", delay: 0.65),
            DemoFrame(filename: "matrix-arcade-dark-observe-580.png", delay: 0.55),
            DemoFrame(filename: "matrix-arcade-dark-act-580.png", delay: 0.55),
            DemoFrame(filename: "transition-arcade-dark-critical.png", delay: 0.55),
            DemoFrame(filename: "matrix-arcade-dark-act-850.png", delay: 0.55),
            DemoFrame(filename: "matrix-arcade-dark-verify-850.png", delay: 0.65),
            DemoFrame(filename: "complete-arcade-dark-verified.png", delay: 1.05)
        ]
    )
]

private func image(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func writeGIF(framesDirectory: URL, output: URL, frames: [DemoFrame]) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        output as CFURL,
        UTType.gif.identifier as CFString,
        frames.count,
        nil
    ) else {
        throw NSError(domain: "PowerModeDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create GIF destination"])
    }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for frame in frames {
        let source = framesDirectory.appendingPathComponent(frame.filename)
        guard let cgImage = image(at: source) else {
            throw NSError(domain: "PowerModeDemo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing frame: \(frame.filename)"])
        }
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frame.delay,
                kCGImagePropertyGIFUnclampedDelayTime: frame.delay
            ]
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
    }
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "PowerModeDemo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize GIF"])
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: compose-demo <frames-directory> <output-directory>\n", stderr)
    exit(2)
}

let framesDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for demo in demos {
    try writeGIF(
        framesDirectory: framesDirectory,
        output: outputDirectory.appendingPathComponent(demo.filename),
        frames: demo.frames
    )
}
fputs("Rendered synthetic Focus and Arcade demos to \(outputDirectory.path)\n", stdout)
