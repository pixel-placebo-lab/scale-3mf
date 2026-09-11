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
    case unknownMetric(String, FastenerType)

    var errorDescription: String? {
        switch self {
        case .not3MF(let url): return "Not a .3mf file: \(url.lastPathComponent)"
        case .readFailed(let url, let err): return "Could not read \(url.lastPathComponent): \(err.localizedDescription)"
        case .archiveFailed(let msg): return "Archive error: \(msg)"
        case .noModelEntry: return "3MF archive missing .model files in 3D/"
        case .xmlParseFailed(let err): return "XML parse failed: \(err.localizedDescription)"
        case .writeFailed(let url, let err): return "Could not write \(url.lastPathComponent): \(err.localizedDescription)"
        case .unknownSae(let s, let t): return "Unknown SAE size '\(s)' for fastener type '\(t.rawValue)'"
        case .unknownMetric(let m, let t): return "Unknown metric size '\(m)' for fastener type '\(t.rawValue)'"
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
    // MARK: - Simple mode (existing)

    static func scale(input: URL, sae: String, type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let entry = ConversionTable.entry(forSae: sae, type: type) else {
            throw Scale3MFError.unknownSae(sae, type)
        }
        let saeFile = entry.sae.replacingOccurrences(of: "/", with: "-")
        let (result, transformScaled) = try scale(input: input, factor: entry.scaleFactor, zFactor: zFactor, targetLabel: saeFile)
        return ConversionResult(input: input, output: result, sae: entry.sae, metric: entry.metric,
                                scaleFactor: entry.scaleFactor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    static func scaleWithFactor(input: URL, factor: Double, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let (result, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: "custom")
        return ConversionResult(input: input, output: result, sae: "custom", metric: "custom",
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    // MARK: - Advanced conversions (all four directions)

    /// Metric source → metric target (e.g. M3 model scaled to M5).
    static func scaleAdvancedMetricToMetric(input: URL, sourceMetric: String, targetMetric: String,
                              type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let sourceDim = ConversionTable.metricDimension(for: sourceMetric, type: type), sourceDim > 0 else {
            throw Scale3MFError.unknownMetric(sourceMetric, type)
        }
        guard let targetDim = ConversionTable.metricDimension(for: targetMetric, type: type), targetDim > 0 else {
            throw Scale3MFError.unknownMetric(targetMetric, type)
        }
        let factor = targetDim / sourceDim
        let label = targetMetric  // target at front of filename
        let (output, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: label)
        return ConversionResult(input: input, output: output, sae: targetMetric, metric: sourceMetric,
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    /// Metric source → SAE target (e.g. M8 model scaled to 3/8").
    static func scaleAdvancedMetricToSAE(input: URL, sourceMetric: String, sae: String,
                              type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let sourceDim = ConversionTable.metricDimension(for: sourceMetric, type: type), sourceDim > 0 else {
            throw Scale3MFError.unknownMetric(sourceMetric, type)
        }
        guard let targetDim = ConversionTable.saeDimension(for: sae, type: type), targetDim > 0 else {
            throw Scale3MFError.unknownSae(sae, type)
        }
        let factor = targetDim / sourceDim
        let label = sae.replacingOccurrences(of: "/", with: "-")
        let (output, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: label)
        return ConversionResult(input: input, output: output, sae: sae, metric: sourceMetric,
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    /// SAE source → metric target (e.g. 1/4" model scaled to M6).
    static func scaleAdvancedSAEToMetric(input: URL, saeSource: String, targetMetric: String,
                              type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let sourceDim = ConversionTable.saeDimension(for: saeSource, type: type), sourceDim > 0 else {
            throw Scale3MFError.unknownSae(saeSource, type)
        }
        guard let targetDim = ConversionTable.metricDimension(for: targetMetric, type: type), targetDim > 0 else {
            throw Scale3MFError.unknownMetric(targetMetric, type)
        }
        let factor = targetDim / sourceDim
        let label = targetMetric  // target at front
        let (output, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: label)
        return ConversionResult(input: input, output: output, sae: targetMetric, metric: saeSource,
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    /// SAE source → SAE target (e.g. 1/4" model scaled to 5/16").
    static func scaleAdvancedSAEToSAE(input: URL, saeSource: String, saeTarget: String,
                              type: FastenerType = .hexHead, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let sourceDim = ConversionTable.saeDimension(for: saeSource, type: type), sourceDim > 0 else {
            throw Scale3MFError.unknownSae(saeSource, type)
        }
        guard let targetDim = ConversionTable.saeDimension(for: saeTarget, type: type), targetDim > 0 else {
            throw Scale3MFError.unknownSae(saeTarget, type)
        }
        let factor = targetDim / sourceDim
        let label = saeTarget.replacingOccurrences(of: "/", with: "-")
        let (output, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: label)
        return ConversionResult(input: input, output: output, sae: saeTarget, metric: saeSource,
                                scaleFactor: factor, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    // MARK: - 8020 Extrusion Profile scaling

    /// Scale 3MF for an 8020 extrusion profile preset (metric→imperial or imperial→metric).
    static func scaleProfile(input: URL, presetKey: String, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let profile = ConversionTable.extrusionProfile(forKey: presetKey) else {
            throw Scale3MFError.archiveFailed("Unknown profile preset: \(presetKey)")
        }
        let label = presetKey  // e.g. "2020-to-1010"
        let (output, transformScaled) = try scale(input: input, factor: profile.scale, zFactor: zFactor, targetLabel: label)
        return ConversionResult(input: input, output: output, sae: presetKey, metric: presetKey,
                                scaleFactor: profile.scale, zScaleFactor: zFactor, transformScaled: transformScaled)
    }

    // MARK: - Core scaling engine

    private static func scale(input: URL, factor: Double, zFactor: Double = 1.0, targetLabel: String = "") throws -> (URL, Bool) {
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
        var outputName = ""
        if !targetLabel.isEmpty {
            // Target label at the BEGINNING for easy finding
            outputName = "\(targetLabel)_\(stem)_s\(String(format: "%.3f", factor))"
        } else {
            outputName = "\(stem)_s\(String(format: "%.3f", factor))"
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

        // 3MF numbers: decimal of arbitrary precision (spec §3.3) — accept
        // sign, leading/trailing decimal point, and exponent forms like 1e0.
        // The outer parens make each interpolated element a capture group.
        let num = "([-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)"

        // transform="m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32" — a
        // row-major 4×3 matrix: rows 0–2 are the images of the basis vectors,
        // row 3 is the translation (3MF core spec §3.3).
        let transformPattern = try! NSRegularExpression(
            pattern: "transform=\"\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)\\s+\(num)",
            options: []
        )

        var anyScaled = false
        var result = xml

        // Scale transforms: world-space scaling is M·S on the row-major 4×3
        // matrix — column j (values at indexes j, j+3, j+6, j+9) scales by its
        // axis factor, so rotated objects scale without shear and the
        // translation follows.
        let axisScales = [factor, factor, zFactor]
        result = replaceMatches(pattern: transformPattern, in: result) { match, str in
            guard let fullRange = Range(match.range, in: str) else { return "" }
            let original = String(str[fullRange])
            var vals = [Double](repeating: 0, count: 12)
            for i in 0..<12 {
                guard let r = Range(match.range(at: i + 1), in: str), let d = Double(str[r]) else {
                    return original  // unparseable: leave the transform untouched
                }
                vals[i] = d
            }
            anyScaled = true
            let out = (0..<12).map { String(format: "%g", vals[$0] * axisScales[$0 % 3]) }
            return "transform=\"" + out.joined(separator: " ") + "\""
        }

        // Vertex scaling is decided per object: an object placed by a
        // transform-carrying <item>/<component> reference is scaled through
        // its matrix (vertices untouched — no double scaling); every other
        // object gets its vertices scaled directly. x/y/z attributes are
        // matched by name, so attribute order and extra attributes survive.
        let refPattern = try! NSRegularExpression(pattern: "<(?:item|component)\\b([^>]*)>", options: [])
        let refIdPattern = try! NSRegularExpression(pattern: "\\bobjectid\\s*=\\s*\"([^\"]*)\"", options: [])
        let transformAttrPattern = try! NSRegularExpression(pattern: "\\btransform\\s*=", options: [])

        var transformedIds = Set<String>()
        refPattern.enumerateMatches(in: result, options: [], range: NSRange(location: 0, length: (result as NSString).length)) { match, _, _ in
            guard let match = match, let attrsRange = Range(match.range(at: 1), in: result) else { return }
            let attrs = String(result[attrsRange])
            guard let idMatch = refIdPattern.firstMatch(in: attrs, options: [], range: NSRange(location: 0, length: (attrs as NSString).length)),
                  let idRange = Range(idMatch.range(at: 1), in: attrs) else { return }
            if transformAttrPattern.firstMatch(in: attrs, options: [], range: NSRange(location: 0, length: (attrs as NSString).length)) != nil {
                transformedIds.insert(String(attrs[idRange]))
            }
        }

        let objectPattern = try! NSRegularExpression(pattern: "<object\\b[^>]*>.*?</object>", options: [.dotMatchesLineSeparators])
        let objectIdPattern = try! NSRegularExpression(pattern: "\\bid\\s*=\\s*\"([^\"]*)\"", options: [])
        let vertexTagPattern = try! NSRegularExpression(pattern: "<vertex\\b[^>]*>", options: [])
        let vertexAttrPattern = try! NSRegularExpression(pattern: "\\b([xyz])\\s*=\\s*\"([^\"]*)\"", options: [])

        result = replaceMatches(pattern: objectPattern, in: result) { match, str in
            guard let blockRange = Range(match.range, in: str) else { return "" }
            let block = String(str[blockRange])
            if let idMatch = objectIdPattern.firstMatch(in: block, options: [], range: NSRange(location: 0, length: (block as NSString).length)),
               let idRange = Range(idMatch.range(at: 1), in: block),
               transformedIds.contains(String(block[idRange])) {
                return block  // scaled via its transform matrix
            }
            return replaceMatches(pattern: vertexTagPattern, in: block) { vmatch, vstr in
                guard let tagRange = Range(vmatch.range, in: vstr) else { return "" }
                let tag = String(vstr[tagRange])
                return replaceMatches(pattern: vertexAttrPattern, in: tag) { amatch, astr in
                    guard let axisRange = Range(amatch.range(at: 1), in: astr),
                          let valueRange = Range(amatch.range(at: 2), in: astr) else { return "" }
                    let axis = String(astr[axisRange])
                    guard let value = Double(astr[valueRange]) else {
                        return String(astr[Range(amatch.range, in: astr)!])  // non-numeric: untouched
                    }
                    anyScaled = true
                    let scale = axis == "z" ? zFactor : factor
                    return "\(axis)=\"\(String(format: "%g", value * scale))\""
                }
            }
        }

        let scaledData = result.data(using: .utf8) ?? data
        return (scaledData, anyScaled)
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