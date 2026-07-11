import Foundation
import SwiftUI

// ─── CLI Entry Point ─────────────────────────────────────────────────
//
// Scale3MF is both a GUI droplet app and a CLI tool.
// When launched with command-line arguments, it runs as CLI.
// When launched with no arguments, it opens the SwiftUI GUI.
//
// CLI features match the Python scale_3mf.py CLI:
//   --version, --help, --table, --fastener-type, --sae, --metric,
//   --target-metric, --target-sae, --factor, --z, -o, --dry-run,
//   --profile-table, --profile-scale, --list-metrics

let args = Array(CommandLine.arguments.dropFirst())

// No arguments → launch GUI
guard !args.isEmpty else {
    NSApplication.shared.setActivationPolicy(.regular)
    Scale3MFApp.main()
    exit(0)
}

// ─── Helpers ─────────────────────────────────────────────────────────

let cliVersion = ConversionTable.appVersion

func printVersion() {
    print("Scale3MF \(cliVersion)")
    print("Built: \(buildDateString())")
}

func buildDateString() -> String {
    // Build timestamp from compile date
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

func printHelp() {
    print("""
    Scale3MF \(cliVersion) — Scale 3MF files for fastener & profile conversion

    USAGE:
        Scale3MF [OPTIONS] [input.3mf]

    OPTIONS:
        --version                   Print version and exit
        --help                      Print this help and exit
        --table                     Print conversion table and exit
        --list-metrics              List available metric sizes for fastener type
        --fastener-type <TYPE>      Fastener type (default: hex_head)
                                    Types: hex_head, hex_nut, nylock_nut,
                                    socket_head_cap, button_head_cap
        --sae <SIZE>                SAE bolt size (e.g. 5/16, 3/8, 1/2)
        --metric <SIZE>             Source metric size (e.g. M8, M10)
        --target-metric <SIZE>      Target metric size (e.g. M5)
        --target-sae <SIZE>         Target SAE size (e.g. 3/8)
        --factor <FACTOR>           Manual X/Y scale factor
        --z <FACTOR>                Z scale factor (default: 1.0)
        -o, --output <PATH>         Output 3MF file path
        --dry-run                   Show what would be done without writing

    PROFILE OPTIONS (8020 Extrusion):
        --profile-table             Print 8020 extrusion profile table and exit
        --profile-scale <PRESET>    Scale for 8020 profile conversion
                                    Presets: 2020-to-1010, 2020-to-1515,
                                    2040-to-1020, 2040-to-1540,
                                    1010-to-2020, 1515-to-2020,
                                    1020-to-2040, 1540-to-2040

    CONVERSION DIRECTIONS:
        Metric→SAE:   --metric M8 --sae 3/8       (or --metric M8 --target-sae 3/8)
        Metric→Metric: --metric M3 --target-metric M5
        SAE→Metric:   --sae 1/4 --target-metric M6
        SAE→SAE:      --sae 1/4 --target-sae 5/16
        Default:      --sae 3/8                   (auto-picks closest metric)

    EXAMPLES:
        Scale3MF --table
        Scale3MF --table --fastener-type hex_nut
        Scale3MF --list-metrics --fastener-type socket_head_cap
        Scale3MF model.3mf --sae 5/16
        Scale3MF model.3mf --sae 5/16 --fastener-type nylock_nut
        Scale3MF model.3mf --sae 5/16 --z 0.95
        Scale3MF model.3mf --metric M3 --target-metric M5
        Scale3MF model.3mf --factor 0.977 -o output.3mf
        Scale3MF model.3mf --sae 5/16 --dry-run
        Scale3MF --profile-table
        Scale3MF model.3mf --profile-scale 2020-to-1010
    """)
}

func parseFastenerType(_ s: String) -> FastenerType? {
    return FastenerType(rawValue: s)
}

func errorExit(_ msg: String) -> Never {
    FileHandle.standardError.write("Error: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

// ─── Argument Parsing ────────────────────────────────────────────────

if args.contains("--version") {
    printVersion()
    exit(0)
}

if args.contains("--help") || args.contains("-h") {
    printHelp()
    exit(0)
}

if args.contains("--profile-table") {
    printProfileTable()
    exit(0)
}

if args.contains("--list-metrics") {
    let type = parseFastenerType(argValue(args, "--fastener-type") ?? "hex_head") ?? .hexHead
    let sizes = ConversionTable.metricSizes(for: type)
    print("Available metric sizes for \(type.rawValue):")
    print("  " + sizes.joined(separator: ", "))
    exit(0)
}

if args.contains("--table") {
    let type = parseFastenerType(argValue(args, "--fastener-type") ?? "hex_head") ?? .hexHead
    if let targetMetric = argValue(args, "--target-metric") {
        print(ConversionTable.formattedMetricTable(type: type, targetMetric: targetMetric))
    } else {
        print(ConversionTable.formattedTable(type: type))
    }
    exit(0)
}

// ─── Scale Operation ─────────────────────────────────────────────────

var inputPath: String?
var sae: String?
var metric: String?
var targetMetric: String?
var targetSae: String?
var fastenerType: FastenerType = .hexHead
var factor: Double?
var zFactor: Double = 1.0
var outputPath: String?
var dryRun = false
var profileScale: String?

var i = 0
while i < args.count {
    let arg = args[i]
    switch arg {
    case "--sae":
        i += 1; if i < args.count { sae = args[i] }
    case "--metric":
        i += 1; if i < args.count { metric = args[i] }
    case "--target-metric":
        i += 1; if i < args.count { targetMetric = args[i] }
    case "--target-sae":
        i += 1; if i < args.count { targetSae = args[i] }
    case "--fastener-type":
        i += 1
        if i < args.count {
            if let t = parseFastenerType(args[i]) {
                fastenerType = t
            } else {
                errorExit("Unknown fastener type '\(args[i])'. Valid: \(FastenerType.allCases.map { $0.rawValue }.joined(separator: ", "))")
            }
        }
    case "--factor":
        i += 1; if i < args.count { factor = Double(args[i]) }
    case "--z":
        i += 1; if i < args.count { zFactor = Double(args[i]) ?? 1.0 }
    case "-o", "--output":
        i += 1; if i < args.count { outputPath = args[i] }
    case "--dry-run":
        dryRun = true
    case "--profile-scale":
        i += 1; if i < args.count { profileScale = args[i] }
    default:
        if arg.hasSuffix(".3mf") {
            inputPath = arg
        } else if !arg.hasPrefix("-") {
            // Treat as input file if it exists
            if FileManager.default.fileExists(atPath: arg) {
                inputPath = arg
            }
        }
    }
    i += 1
}

// Validate arguments
if targetMetric != nil && targetSae != nil {
    errorExit("--target-metric and --target-sae are mutually exclusive")
}

if profileScale != nil {
    // 8020 profile scaling
    guard let preset = profileScale,
          ConversionTable.extrusionProfile(forKey: preset) != nil else {
        errorExit("Unknown profile preset. Use --profile-table to see available presets.")
    }
    guard let inputPath = inputPath else {
        errorExit("--profile-scale requires an input 3MF file")
    }
    let inputURL = URL(fileURLWithPath: inputPath)
    guard FileManager.default.fileExists(atPath: inputPath) else {
        errorExit("File not found: \(inputPath)")
    }
    if dryRun {
        print("Dry run: would scale \(inputPath) with profile \(preset)")
        if let p = ConversionTable.extrusionProfile(forKey: preset) {
            print("  Source: \(p.sourceLabel)")
            print("  Target: \(p.targetLabel)")
            print("  Body scale: \(String(format: "%.4f", p.scale)) (\(String(format: "%+.2f%%", (p.scale - 1) * 100)))")
            let actualSlot = p.sourceSlot * p.scale
            let diff = actualSlot - p.targetSlot
            print("  T-slot after scale: \(String(format: "%.2f", actualSlot))mm (target: \(String(format: "%.2f", p.targetSlot))mm, diff: \(String(format: "%+.2f", diff))mm)")
            if abs(diff) > 0.1 {
                print("  ⚠️  T-slot \(diff > 0 ? "oversized" : "undersized") — uniform scaling cannot fix slots")
            }
        }
        print("  (dry run — no output written)")
        exit(0)
    }
    do {
        let result = try Converter.scaleProfile(input: inputURL, presetKey: preset, zFactor: zFactor)
        if let outPath = outputPath {
            let outURL = URL(fileURLWithPath: outPath)
            if FileManager.default.fileExists(atPath: outURL.path) {
                try FileManager.default.removeItem(at: outURL)
            }
            try FileManager.default.moveItem(at: result.output, to: outURL)
            print("Wrote \(outURL.path)")
        } else {
            print("Wrote \(result.output.path)")
        }
        print("Scale factor: \(String(format: "%.4f", result.scaleFactor))")
        if zFactor != 1.0 { print("Z scale: \(String(format: "%.4f", zFactor))") }
        exit(0)
    } catch {
        errorExit(error.localizedDescription)
    }
}

if factor != nil {
    // Manual factor mode
    guard let inputPath = inputPath else {
        if dryRun {
            print("Dry run: would scale with factor \(String(format: "%.4f", factor!))")
            if zFactor != 1.0 { print("Z scale: \(String(format: "%.4f", zFactor))") }
            print("  (dry run — no output written)")
            exit(0)
        }
        errorExit("--factor requires an input 3MF file")
    }
    let inputURL = URL(fileURLWithPath: inputPath)
    guard FileManager.default.fileExists(atPath: inputPath) else {
        errorExit("File not found: \(inputPath)")
    }
    if dryRun {
        print("Dry run: would scale \(inputPath)")
        print("  X/Y factor: \(String(format: "%.4f", factor!))")
        if zFactor != 1.0 { print("  Z factor: \(String(format: "%.4f", zFactor))") }
        print("  (dry run — no output written)")
        exit(0)
    }
    do {
        let result = try Converter.scaleWithFactor(input: inputURL, factor: factor!, zFactor: zFactor)
        if let outPath = outputPath {
            let outURL = URL(fileURLWithPath: outPath)
            if FileManager.default.fileExists(atPath: outURL.path) {
                try FileManager.default.removeItem(at: outURL)
            }
            try FileManager.default.moveItem(at: result.output, to: outURL)
            print("Wrote \(outURL.path)")
        } else {
            print("Wrote \(result.output.path)")
        }
        print("Scale factor: \(String(format: "%.4f", result.scaleFactor))")
        if zFactor != 1.0 { print("Z scale: \(String(format: "%.4f", zFactor))") }
        exit(0)
    } catch {
        errorExit(error.localizedDescription)
    }
}

// Determine conversion direction
let hasSAE = sae != nil
let hasMetric = metric != nil
let hasTargetMetric = targetMetric != nil
let hasTargetSAE = targetSae != nil

guard hasSAE || hasMetric || hasTargetMetric || hasTargetSAE else {
    printHelp()
    errorExit("Specify --sae, --metric+--target-metric, --sae+--target-metric, --factor, or --profile-scale")
}

guard let inputPath = inputPath else {
    if dryRun {
        print("Dry run — no input file specified")
        exit(0)
    }
    errorExit("No input 3MF file specified")
}

let inputURL = URL(fileURLWithPath: inputPath)
guard FileManager.default.fileExists(atPath: inputPath) else {
    errorExit("File not found: \(inputPath)")
}

if dryRun {
    print("Dry run: \(inputPath)")
    if hasMetric && hasTargetMetric {
        print("  Mode: Metric→Metric")
        print("  Source: \(metric!) → Target: \(targetMetric!)")
        print("  Fastener type: \(fastenerType.rawValue)")
    } else if hasSAE && hasTargetMetric && !hasMetric {
        print("  Mode: SAE→Metric")
        print("  Source: \(sae!) → Target: \(targetMetric!)")
        print("  Fastener type: \(fastenerType.rawValue)")
    } else if hasMetric && hasTargetSAE && !hasSAE {
        print("  Mode: Metric→SAE")
        print("  Source: \(metric!) → Target: \(targetSae!)")
        print("  Fastener type: \(fastenerType.rawValue)")
    } else if hasSAE && hasTargetSAE && !hasMetric {
        print("  Mode: SAE→SAE")
        print("  Source: \(sae!) → Target: \(targetSae!)")
        print("  Fastener type: \(fastenerType.rawValue)")
    } else if hasSAE {
        print("  Mode: Metric→SAE (default closest metric)")
        print("  Target SAE: \(sae!)")
        print("  Fastener type: \(fastenerType.rawValue)")
    }
    if zFactor != 1.0 { print("  Z factor: \(String(format: "%.4f", zFactor))") }
    print("  (dry run — no output written)")
    exit(0)
}

do {
    let result: ConversionResult

    if hasMetric && hasTargetMetric {
        // Metric → Metric
        result = try Converter.scaleAdvancedMetricToMetric(
            input: inputURL, sourceMetric: metric!, targetMetric: targetMetric!,
            type: fastenerType, zFactor: zFactor)
    } else if hasSAE && hasTargetMetric && !hasMetric {
        // SAE → Metric
        result = try Converter.scaleAdvancedSAEToMetric(
            input: inputURL, saeSource: sae!, targetMetric: targetMetric!,
            type: fastenerType, zFactor: zFactor)
    } else if hasMetric && hasTargetSAE && !hasSAE {
        // Metric → SAE (via --target-sae)
        result = try Converter.scaleAdvancedMetricToSAE(
            input: inputURL, sourceMetric: metric!, sae: targetSae!,
            type: fastenerType, zFactor: zFactor)
    } else if hasSAE && hasTargetSAE && !hasMetric {
        // SAE → SAE
        result = try Converter.scaleAdvancedSAEToSAE(
            input: inputURL, saeSource: sae!, saeTarget: targetSae!,
            type: fastenerType, zFactor: zFactor)
    } else if hasSAE {
        // Default: Metric → SAE (auto closest metric)
        result = try Converter.scale(input: inputURL, sae: sae!, type: fastenerType, zFactor: zFactor)
    } else {
        errorExit("Could not determine conversion direction from arguments")
    }

    if let outPath = outputPath {
        let outURL = URL(fileURLWithPath: outPath)
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }
        try FileManager.default.moveItem(at: result.output, to: outURL)
        print("Wrote \(outURL.path)")
    } else {
        print("Wrote \(result.output.path)")
    }
    print("Scale factor: \(String(format: "%.4f", result.scaleFactor))")
    if zFactor != 1.0 { print("Z scale: \(String(format: "%.4f", zFactor))") }
    exit(0)
} catch {
    errorExit(error.localizedDescription)
}

// ─── Utility: arg value extraction ───────────────────────────────────

func argValue(_ args: [String], _ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag) else { return nil }
    let next = idx + 1
    if next < args.count && !args[next].hasPrefix("-") {
        return args[next]
    }
    return nil
}

// ─── Profile table printing ──────────────────────────────────────────

func printProfileTable() {
    print("\n8020 Aluminum Extrusion — Profile Scaling Presets")
    print("=" * 90)
    print(String(format: "%-20@ %-26@ %-26@ %8@ %12@", "Preset", "Source", "Target", "Scale", "Slot After"))
    print("-" * 90)
    for item in ConversionTable.extrusionProfiles {
        let p = item.profile
        let actualSlot = p.sourceSlot * p.scale
        let slotStr = String(format: "%.2fmm", actualSlot)
        let scaleStr = String(format: "%.4f", p.scale)
        print(String(format: "%-20@ %-26@ %-26@ %8@ %12@", item.key, p.sourceLabel, p.targetLabel, scaleStr, slotStr))
    }
    print()
}

// Support String * Int for repeat
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}