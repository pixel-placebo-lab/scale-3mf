import Foundation
import ZIPFoundation

enum Scale3MFError: LocalizedError {
    case not3MF(URL)
    case readFailed(URL, Error)
    case archiveFailed(String)
    case noModelEntry
    case xmlParseFailed(Error)
    case writeFailed(URL, Error)
    case unknownSae(String, FastenerType)

    var errorDescription: String? {
        switch self {
        case .not3MF(let url): return "Not a .3mf file: \(url.lastPathComponent)"
        case .readFailed(let url, let err): return "Could not read \(url.lastPathComponent): \(err.localizedDescription)"
        case .archiveFailed(let msg): return "Archive error: \(msg)"
        case .noModelEntry: return "3MF archive missing .model files in 3D/"
        case .xmlParseFailed(let err): return "XML parse failed: \(err.localizedDescription)"
        case .writeFailed(let url, let err): return "Could not write \(url.lastPathComponent): \(err.localizedDescription)"
        case .unknownSae(let s, let t): return "Unknown SAE size '\(s)' for fastener type '\(t.rawValue)'"
        }
    }
}

struct ConversionResult {
    let input: URL
    let output: URL
    let sae: String
    let metric: String
    let scaleFactor: Double
    let zScaleFactor: Double
    let transformScaled: Bool
}

final class Converter {
    static func scale(input: URL, sae: String, type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let entry = ConversionTable.entry(forSae: sae, type: type) else {
            throw Scale3MFError.unknownSae(sae, type)
        }
        let saeFile = entry.sae.replacingOccurrences(of: "/", with: "-")
        let (result, transformScaled) = try scale(input: input, factor: entry.scaleFactor, zFactor: zFactor, saeLabel: saeFile)
        return ConversionResult(input: input, output: result, sae: entry.sae, metric: entry.metric,
                                scaleFactor: entry.scaleFactor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    static func scaleWithFactor(input: URL, factor: Double, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let (result, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, saeLabel: "custom")
        return ConversionResult(input: input, output: result, sae: "custom", metric: "custom",
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    private static func scale(input: URL, factor: Double, zFactor: Double = 1.0, saeLabel: String = "") throws -> (URL, Bool) {
        let data = try Data(contentsOf: input)
        let archive = try Archive(data: data, accessMode: .read)

        // Find ALL .model files in the archive (3D/3dmodel.model + 3D/Objects/*.model)
        let modelEntries = archive.filter { $0.path.hasSuffix(".model") && $0.path.hasPrefix("3D/") }
        guard !modelEntries.isEmpty else {
            throw Scale3MFError.noModelEntry
        }

        var anyTransformScaled = false
        var scaledFiles: [(path: String, data: Data)] = []

        for entry in modelEntries {
            var modelData = Data()
            _ = try archive.extract(entry) { chunk in modelData.append(chunk) }
            let (scaledData, transformScaled) = scaleModelXML(modelData, factor: factor, zFactor: zFactor)
            if transformScaled { anyTransformScaled = true }
            scaledFiles.append((entry.path, scaledData))
        }

        let stem = input.deletingPathExtension().lastPathComponent
        var outputName = "\(stem)_s\(String(format: "%.3f", factor))"
        if !saeLabel.isEmpty {
            outputName += "_\(saeLabel)"
        }
        if zFactor != 1.0 {
            outputName += "_z\(String(format: "%.3f", zFactor))"
        }
        outputName += ".3mf"
        let output = input.deletingLastPathComponent().appendingPathComponent(outputName)

        // Create a new archive: copy all entries, replacing scaled .model files
        let scaledMap = Dictionary(uniqueKeysWithValues: scaledFiles)
        let scaledPaths = Set(scaledMap.keys)

        let outArchive = try Archive(data: Data(), accessMode: .create)
        for entry in archive {
            if scaledPaths.contains(entry.path) {
                let sd = scaledMap[entry.path]!
                try outArchive.addEntry(with: entry.path, type: .file,
                    uncompressedSize: Int64(sd.count), modificationDate: Date(), compressionMethod: .deflate,
                    provider: { pos, size in
                        let end = pos + Int64(size)
                        return sd.subdata(in: Int(pos)..<Int(end))
                    })
            } else {
                var entryData = Data()
                _ = try archive.extract(entry) { chunk in entryData.append(chunk) }
                try outArchive.addEntry(with: entry.path, type: entry.type,
                    uncompressedSize: Int64(entryData.count), modificationDate: Date(), compressionMethod: .deflate,
                    provider: { pos, size in
                        let end = pos + Int64(size)
                        return entryData.subdata(in: Int(pos)..<Int(end))
                    })
            }
        }
        guard let outputArchiveData = outArchive.data else {
            throw Scale3MFError.archiveFailed("Could not finalize archive")
        }
        try outputArchiveData.write(to: output)
        return (output, anyTransformScaled)
    }

    // MARK: - Regex-based XML scaling

    private static func scaleModelXML(_ data: Data, factor: Double, zFactor: Double = 1.0) -> (Data, Bool) {
        guard let xml = String(data: data, encoding: .utf8) else { return (data, false) }

        // Transform pattern: transform="r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz"
        let transformPattern = try! NSRegularExpression(
            pattern: "transform=\"(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\"",
            options: []
        )

        // Vertex pattern: <vertex x="..." y="..." z="..."
        let vertexPattern = try! NSRegularExpression(
            pattern: "<vertex\\s+x=\"([-\\d.]+)\"\\s+y=\"([-\\d.]+)\"\\s+z=\"([-\\d.]+)\"",
            options: []
        )

        var transformScaled = false
        var result = xml

        // Scale transforms
        result = replaceMatches(pattern: transformPattern, in: result) { match, str in
            transformScaled = true
            func g(_ i: Int) -> Double {
                guard let r = Range(match.range(at: i), in: str), let d = Double(str[r]) else { return 0 }
                return d
            }
            let r00 = g(1) * factor, r01 = g(2) * factor, r02 = g(3)
            let r10 = g(4) * factor, r11 = g(5) * factor, r12 = g(6)
            let r20 = g(7), r21 = g(8)
            var r22 = g(9)
            var tx = g(10) * factor, ty = g(11) * factor, tz = g(12)
            if zFactor != 1.0 { r22 *= zFactor; tz *= zFactor }
            let fmt = { String(format: "%g", $0) }
            return "transform=\"\(fmt(r00)) \(fmt(r01)) \(fmt(r02)) \(fmt(r10)) \(fmt(r11)) \(fmt(r12)) \(fmt(r20)) \(fmt(r21)) \(fmt(r22)) \(fmt(tx)) \(fmt(ty)) \(fmt(tz))\""
        }

        // Scale vertices (only if no transforms were found in this file)
        var vertexScaled = false
        if !transformScaled {
            result = replaceMatches(pattern: vertexPattern, in: result) { match, str in
                vertexScaled = true
                func g(_ i: Int) -> Double {
                    guard let r = Range(match.range(at: i), in: str), let d = Double(str[r]) else { return 0 }
                    return d
                }
                let sx = g(1) * factor, sy = g(2) * factor
                let sz = zFactor != 1.0 ? g(3) * zFactor : g(3)
                let fmt = { String(format: "%g", $0) }
                return "<vertex x=\"\(fmt(sx))\" y=\"\(fmt(sy))\" z=\"\(fmt(sz))\""
            }
        }

        let scaledData = result.data(using: .utf8) ?? data
        return (scaledData, transformScaled || vertexScaled)
    }

    private static func replaceMatches(pattern: NSRegularExpression, in string: String,
                                        using replacer: (NSTextCheckingResult, String) -> String) -> String {
        var result = ""
        var lastEnd = string.startIndex
        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)
        pattern.enumerateMatches(in: string, options: [], range: range) { match, flags, _ in
            guard let match = match else { return }
            guard let matchRange = Range(match.range, in: string) else { return }
            result += string[lastEnd..<matchRange.lowerBound]
            result += replacer(match, string)
            lastEnd = matchRange.upperBound
        }
        result += string[lastEnd..<string.endIndex]
        return result
    }
}