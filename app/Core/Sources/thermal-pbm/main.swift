import Foundation
import ThermalPrinterCore

let usage = """
    usage: thermal-pbm <image> <out.pbm> [--brightness N] [--contrast X] [--gamma Y] [--rotate 0|90|180|270]
           thermal-pbm --sample <out.pbm> [--brightness N] [--contrast X] [--gamma Y] [--rotate 0|90|180|270]
           thermal-pbm --card <card.json> <out.pbm> [--png <out.png>]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("thermal-pbm: \(message)\n\(usage)\n".utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
var brightness = 0.0
var contrast = 1.0
var gamma = 1.0
var rotation = ImageRotation.degrees0
var useSample = false
var useCard = false
var pngPath: String?
var positional: [String] = []

var index = 0
@MainActor func nextValue(after option: String) -> String {
    index += 1
    guard index < arguments.count else { fail("\(option) needs a value") }
    return arguments[index]
}

@MainActor func nextNumber(after option: String) -> Double {
    let text = nextValue(after: option)
    guard let number = Double(text), number.isFinite else { fail("\(option) needs a number, got \(text)") }
    return number
}

while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--brightness": brightness = nextNumber(after: argument)
    case "--contrast": contrast = nextNumber(after: argument)
    case "--gamma": gamma = nextNumber(after: argument)
    case "--rotate":
        let text = nextValue(after: argument)
        guard let degrees = Int(text), let parsed = ImageRotation(rawValue: degrees) else {
            fail("--rotate must be 0, 90, 180 or 270, got \(text)")
        }
        rotation = parsed
    case "--sample": useSample = true
    case "--card": useCard = true
    case "--png": pngPath = nextValue(after: argument)
    default:
        if argument.hasPrefix("--") { fail("unknown option \(argument)") }
        positional.append(argument)
    }
    index += 1
}

guard gamma > 0 else { fail("--gamma must be greater than 0") }
guard !(useCard && useSample) else { fail("--card and --sample cannot be combined") }
guard pngPath == nil || useCard else { fail("--png is only available with --card") }

let adjust = PhotoAdjust(brightness: brightness, contrast: contrast, gamma: gamma)
let bitmap: Bitmap1
let outputPath: String
do {
    if useCard {
        guard positional.count == 2 else { fail("--card takes a card JSON path and an output path") }
        outputPath = positional[1]
        let json = try Data(contentsOf: URL(fileURLWithPath: positional[0]))
        bitmap = try StripComposer().bitmap(cardJSON: json)
        if let pngPath {
            try PNGWriter.data(bitmap).write(to: URL(fileURLWithPath: pngPath))
        }
    } else if useSample {
        guard positional.count == 1 else { fail("--sample takes exactly one output path") }
        outputPath = positional[0]
        bitmap = try ImageLoader.bitmap(from: ImageLoader.sampleImage(), adjust: adjust, rotation: rotation)
    } else {
        guard positional.count == 2 else { fail("expected an input image and an output path") }
        outputPath = positional[1]
        bitmap = try ImageLoader.bitmap(fromFile: URL(fileURLWithPath: positional[0]), adjust: adjust, rotation: rotation)
    }
    try PBMWriter.data(bitmap).write(to: URL(fileURLWithPath: outputPath))
} catch ImageLoaderError.unreadable {
    fail("cannot read \(positional.first ?? "") as an image")
} catch {
    fail("\(error)")
}

print("wrote \(outputPath) (\(bitmap.width)x\(bitmap.height), \(bitmap.lengthMillimeters) mm)")
