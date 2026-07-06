import Foundation
import SwiftUI

let args = Array(CommandLine.arguments.dropFirst())

var input: String?
var sae: String?
var fastenerType: FastenerType = .hexHead
var factor: Double?
var output: String?
var i = 0
while i < args.count {
    let arg = args[i]
    if arg == "--sae" {
        i += 1
        if i < args.count { sae = args[i] }
    } else if arg == "--fastener-type" {
        i += 1
        if i < args.count, let ft = FastenerType(rawValue: args[i]) {
            fastenerType = ft
        }
    } else if arg == "--factor" {
        i += 1
        if i < args.count { factor = Double(args[i]) }
    } else if arg == "-o" {
        i += 1
        if i < args.count { output = args[i] }
    } else if arg.hasSuffix(".3mf") {
        input = arg
    }
    i += 1
}

if args.contains("--version") {
    print("Scale3MF \(ConversionTable.appVersion)")
    exit(0)
}

if args.contains("--table") {
    print(ConversionTable.formattedTable(type: fastenerType))
    exit(0)
}

if let inputPath = input {
    let inputURL = URL(fileURLWithPath: inputPath)
    do {
        let result: ConversionResult
        if let s = sae {
            result = try Converter.scale(input: inputURL, sae: s, type: fastenerType)
        } else if let f = factor {
            result = try Converter.scaleWithFactor(input: inputURL, factor: f)
        } else {
            result = try Converter.scale(input: inputURL, sae: "5/16", type: fastenerType)
        }

        if let outputPath = output {
            let outputURL = URL(fileURLWithPath: outputPath)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: result.output, to: outputURL)
            print("Wrote \(outputURL.path)")
        } else {
            print("Wrote \(result.output.path)")
        }
        print("Scale factor: \(String(format: "%.4f", result.scaleFactor)) (metric \(result.metric))")
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

// No CLI arguments: launch SwiftUI app.
NSApplication.shared.setActivationPolicy(.regular)
NSApp.setActivationPolicy(.regular)
Scale3MFApp.main()
