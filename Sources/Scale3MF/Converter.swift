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
    case noHexPocket
    case analyzeFailed(String)

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
        case .noHexPocket: return "No hexagonal pocket detected — is this a fastener knob?"
        case .analyzeFailed(let msg): return "Analysis failed: \(msg)"
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

// Measure mode result — includes detected pocket info
struct MeasureResult {
    let input: URL
    let output: URL
    let detectedAF: Double
    let targetAF: Double
    let clearance: Double
    let scaleFactor: Double
    let zScaleFactor: Double
    let pocketZ: Double
    let transformScaled: Bool
}

// Hex pocket detection result
struct HexFeature: Identifiable, Hashable {
    let id = UUID()
    let afMM: Double
    let zHeight: Double
    let circumradius: Double
    let vertexCount: Int
    let centerX: Double
    let centerY: Double

    var isLikelyPocket: Bool { afMM >= 4.0 && afMM <= 30.0 }
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

    // MARK: - Measure Mode

    /// Analyze a 3MF file for hexagonal pockets.
    static func analyzeHexPockets(in input: URL) throws -> [HexFeature] {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let vertices = try extractVertices(from: input)
        if vertices.isEmpty {
            throw Scale3MFError.analyzeFailed("No vertices found in 3MF file")
        }
        return HexPocketAnalyzer.findHexagons(in: vertices)
    }

    /// Measure mode: auto-detect hex pocket AF and scale to user-specified target.
    static func scaleMeasure(input: URL, targetAF: Double, clearance: Double = 0.15,
                             zFactor: Double = 1.0) throws -> MeasureResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let hexagons = try analyzeHexPockets(in: input)
        guard let pocket = HexPocketAnalyzer.findBoltPocket(in: hexagons) else {
            throw Scale3MFError.noHexPocket
        }

        let totalTarget = targetAF + clearance
        let factor = totalTarget / pocket.afMM
        let label = String(format: "measured_%.2f", totalTarget)
        let (output, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor, targetLabel: label)

        return MeasureResult(input: input, output: output,
                             detectedAF: pocket.afMM, targetAF: targetAF,
                             clearance: clearance, scaleFactor: factor,
                             zScaleFactor: zFactor, pocketZ: pocket.zHeight,
                             transformScaled: transformScaled)
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

    // MARK: - Vertex Extraction (for Measure mode)

    private static func extractVertices(from input: URL) throws -> [(Double, Double, Double)] {
        let data = try Data(contentsOf: input)
        let archive = try Archive(data: data, accessMode: .read)
        let modelEntries = archive.filter { $0.path.hasSuffix(".model") && $0.path.hasPrefix("3D/") }
        guard !modelEntries.isEmpty else {
            throw Scale3MFError.noModelEntry
        }

        var allVertices: [(Double, Double, Double)] = []

        for entry in modelEntries {
            var modelData = Data()
            _ = try archive.extract(entry) { chunk in modelData.append(chunk) }
            guard let xml = String(data: modelData, encoding: .utf8) else { continue }

            // Extract transform matrices
            let transformPattern = try! NSRegularExpression(
                pattern: "transform=\"([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\\s+([\\S]+)\"",
                options: []
            )
            var transforms: [[Double]] = []
            let nsXml = xml as NSString
            transformPattern.enumerateMatches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length)) { match, _, _ in
                guard let match = match else { return }
                var t: [Double] = []
                for i in 1...12 {
                    guard let r = Range(match.range(at: i), in: xml), let d = Double(xml[r]) else { return }
                    t.append(d)
                }
                transforms.append(t)
            }

            // Extract vertices
            let vertexPattern = try! NSRegularExpression(
                pattern: "<vertex\\s+x=\"([ -\\d.]+)\"\\s+y=\"([ -\\d.]+)\"\\s+z=\"([ -\\d.]+)\"",
                options: []
            )
            var fileVerts: [(Double, Double, Double)] = []
            vertexPattern.enumerateMatches(in: xml, options: [], range: NSRange(location: 0, length: nsXml.length)) { match, _, _ in
                guard let match = match else { return }
                func g(_ i: Int) -> Double {
                    guard let r = Range(match.range(at: i), in: xml), let d = Double(xml[r]) else { return 0 }
                    return d
                }
                fileVerts.append((g(1), g(2), g(3)))
            }

            // Apply first transform if present (simple single-object 3MF)
            if let t = transforms.first, fileVerts.count > 0 {
                let r00 = t[0], r01 = t[1], r02 = t[2]
                let r10 = t[3], r11 = t[4], r12 = t[5]
                let r20 = t[6], r21 = t[7], r22 = t[8]
                let tx = t[9], ty = t[10], tz = t[11]
                for (x, y, z) in fileVerts {
                    let wx = r00*x + r01*y + r02*z + tx
                    let wy = r10*x + r11*y + r12*z + ty
                    let wz = r20*x + r21*y + r22*z + tz
                    allVertices.append((wx, wy, wz))
                }
            } else {
                allVertices.append(contentsOf: fileVerts)
            }
        }
        return allVertices
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
            pattern: "<vertex\\s+x=\"([ -\\d.]+)\"\\s+y=\"([ -\\d.]+)\"\\s+z=\"([ -\\d.]+)\"",
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

// MARK: - Hex Pocket Analyzer

final class HexPocketAnalyzer {
    /// Find hexagonal pockets in vertex data.
    /// Groups vertices by Z layer, finds 6-vertex groups at 60° spacing.
    static func findHexagons(in vertices: [(Double, Double, Double)]) -> [HexFeature] {
        if vertices.count < 6 { return [] }

        let tolerance: Double = 0.01

        // Group by Z layer
        var zLayers: [Double: [(Double, Double, Double)]] = [:]
        for v in vertices {
            let zKey = (v.2 / tolerance).rounded() * tolerance
            zLayers[zKey, default: []].append(v)
        }

        var hexagons: [HexFeature] = []

        for (zKey, layerVerts) in zLayers {
            if layerVerts.count < 6 { continue }
            let n = layerVerts.count

            for i in 0..<n {
                for j in (i+1)..<n {
                    let v1 = layerVerts[i]
                    let v2 = layerVerts[j]
                    let dx = v2.0 - v1.0
                    let dy = v2.1 - v1.1
                    let dist = (dx*dx + dy*dy).squareRoot()
                    if dist < 1.0 { continue }

                    let r = dist / 2.0  // circumradius
                    if r < 2.0 || r > 30.0 { continue }

                    let cx = (v1.0 + v2.0) / 2.0
                    let cy = (v1.1 + v2.1) / 2.0

                    // Find all vertices at ~r from center
                    var group: [(Double, Double, Double)] = []
                    for v in layerVerts {
                        let vdx = v.0 - cx
                        let vdy = v.1 - cy
                        let vr = (vdx*vdx + vdy*vdy).squareRoot()
                        if abs(vr - r) < tolerance * 5 {
                            group.append(v)
                        }
                    }
                    if group.count < 6 { continue }

                    // Check for 6 angles at ~60° spacing
                    var angles: [Double] = []
                    for v in group {
                        angles.append(atan2(v.1 - cy, v.0 - cx))
                    }
                    angles.sort()

                    var bestCount = 0
                    for startIdx in 0..<angles.count {
                        var count = 1
                        var target = angles[startIdx] + .pi / 3
                        for _ in 1..<6 {
                            var bestDiff = Double.infinity
                            for a in angles {
                                let diff = abs(((a - target + .pi).truncatingRemainder(dividingBy: 2 * .pi)) - .pi)
                                if diff < bestDiff { bestDiff = diff }
                            }
                            if bestDiff < 3.0 * .pi / 180 {  // 3° tolerance
                                count += 1
                                target += .pi / 3
                            } else {
                                break
                            }
                        }
                        bestCount = max(bestCount, count)
                    }

                    if bestCount >= 6 {
                        let af = r * 3.0.squareRoot()
                        // Deduplicate
                        let isDup = hexagons.contains { h in
                            abs(h.afMM - af) < 0.1 && abs(h.zHeight - zKey) < 0.5
                        }
                        if !isDup {
                            hexagons.append(HexFeature(
                                afMM: af, zHeight: zKey, circumradius: r,
                                vertexCount: 6, centerX: cx, centerY: cy))
                        }
                    }
                }
            }
        }

        hexagons.sort { $0.afMM < $1.afMM }
        return hexagons
    }

    /// Find the most likely bolt pocket (smallest AF in bolt-size range).
    static func findBoltPocket(in hexagons: [HexFeature]) -> HexFeature? {
        let candidates = hexagons.filter { $0.isLikelyPocket }
        return candidates.first ?? hexagons.first
    }
}