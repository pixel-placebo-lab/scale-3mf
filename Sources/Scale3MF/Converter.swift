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
        case .noModelEntry: return "3MF archive missing 3D/3dmodel.model"
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

        let (result, transformScaled) = try scale(input: input, factor: entry.scaleFactor, zFactor: zFactor)
        return ConversionResult(input: input,
                                output: result,
                                sae: entry.sae,
                                metric: entry.metric,
                                scaleFactor: entry.scaleFactor,
                                zScaleFactor: zFactor,
                                transformScaled: transformScaled)
    }

    static func scaleWithFactor(input: URL, factor: Double, zFactor: Double = 1.0) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let (result, transformScaled) = try scale(input: input, factor: factor, zFactor: zFactor)
        return ConversionResult(input: input,
                                output: result,
                                sae: "custom",
                                metric: "custom",
                                scaleFactor: factor,
                                zScaleFactor: zFactor,
                                transformScaled: transformScaled)
    }

    private static func scale(input: URL, factor: Double, zFactor: Double = 1.0) throws -> (URL, Bool) {
        let data = try Data(contentsOf: input)
        let archive = try Archive(data: data, accessMode: .update)

        guard let modelEntry = archive["3D/3dmodel.model"] else {
            throw Scale3MFError.noModelEntry
        }

        var modelData = Data()
        _ = try archive.extract(modelEntry) { chunk in modelData.append(chunk) }

        let (scaledData, transformScaled) = try scaleModelXML(modelData, factor: factor, zFactor: zFactor)

        let stem = input.deletingPathExtension().lastPathComponent
        var outputName = "\(stem)_s\(String(format: "%.3f", factor)).3mf"
        if zFactor != 1.0 {
            outputName = "\(stem)_s\(String(format: "%.3f", factor))_z\(String(format: "%.3f", zFactor)).3mf"
        }
        let output = input.deletingLastPathComponent().appendingPathComponent(outputName)

        try archive.remove(modelEntry)
        try archive.addEntry(with: "3D/3dmodel.model",
                              type: .file,
                              uncompressedSize: Int64(scaledData.count),
                              modificationDate: Date(),
                              compressionMethod: .deflate,
                              provider: { position, size in
                                  let end = position + Int64(size)
                                  return scaledData.subdata(in: Int(position)..<Int(end))
                              })
        guard let outputArchiveData = archive.data else {
            throw Scale3MFError.archiveFailed("Could not finalize archive")
        }
        try outputArchiveData.write(to: output)

        return (output, transformScaled)
    }

    private static func scaleModelXML(_ data: Data, factor: Double, zFactor: Double = 1.0) throws -> (Data, Bool) {
        let parser = XMLParser(data: data)
        let delegate = ModelXMLScaler(factor: factor, zFactor: zFactor)
        parser.delegate = delegate
        parser.parse()
        if let err = parser.parserError {
            throw Scale3MFError.xmlParseFailed(err)
        }
        return (delegate.outputData, delegate.transformScaled)
    }
}

private final class ModelXMLScaler: NSObject, XMLParserDelegate {
    let factor: Double
    let zFactor: Double
    var output = Data()
    var transformScaled = false
    var currentElement: String?
    var elementIsEmpty: Bool = false
    var pendingTag: String?

    init(factor: Double, zFactor: Double = 1.0) {
        self.factor = factor
        self.zFactor = zFactor
        super.init()
    }

    var outputData: Data { output }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        var attrs = attributeDict

        if elementName == "vertex" {
            if let x = attrs["x"], let y = attrs["y"] {
                attrs["x"] = scaleString(x)
                attrs["y"] = scaleString(y)
                if zFactor != 1.0, let z = attrs["z"] {
                    attrs["z"] = scaleStringZ(z)
                }
            }
        } else if elementName == "item" {
            if let transform = attrs["transform"] {
                attrs["transform"] = scaleTransform(transform)
                transformScaled = true
            }
        }

        // Build opening tag but DON'T close with ">" yet — we need to determine
        // if this is a self-closing element (no character content).
        var tag = "<\(elementName)"
        for (key, value) in attrs {
            let escaped = value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            tag += " \(key)=\"\(escaped)\""
        }
        pendingTag = tag
        elementIsEmpty = true
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // If we have a pending tag and this is the first content, close the opening tag.
        if let pending = pendingTag {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let data = (pending + ">").data(using: .utf8) {
                    output.append(data)
                }
                pendingTag = nil
                elementIsEmpty = false
            } else {
                // Whitespace-only characters — could be formatting between child elements.
                // Don't close yet; but also don't emit whitespace as content for empty elements.
                // We'll emit it only if the element turns out to have children.
                return
            }
        }
        if let data = string.data(using: .utf8) {
            output.append(data)
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // If we have a pending tag, close it first
        if let pending = pendingTag {
            if let data = (pending + ">").data(using: .utf8) {
                output.append(data)
            }
            pendingTag = nil
            elementIsEmpty = false
        }
        output.append(CDATABlock)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let pending = pendingTag {
            // No characters were found — self-closing element
            if let data = (pending + "/>").data(using: .utf8) {
                output.append(data)
            }
            pendingTag = nil
        } else {
            // Element had content — emit closing tag
            if let data = "</\(elementName)>".data(using: .utf8) {
                output.append(data)
            }
        }
        elementIsEmpty = false
        currentElement = nil
    }

    // MARK: - Comment handling

    func parser(_ parser: XMLParser, foundComment commentText: String) {
        // If we have a pending tag, close it first (comments can appear inside elements)
        if let pending = pendingTag {
            if let data = (pending + ">").data(using: .utf8) {
                output.append(data)
            }
            pendingTag = nil
            elementIsEmpty = false
        }
        if let data = "<!--\(commentText)-->".data(using: .utf8) {
            output.append(data)
        }
    }

    private func scaleString(_ value: String) -> String {
        guard let d = Double(value) else { return value }
        return String(format: "%g", d * factor)
    }

    private func scaleStringZ(_ value: String) -> String {
        guard let d = Double(value) else { return value }
        return String(format: "%g", d * zFactor)
    }

    private func scaleTransform(_ transform: String) -> String {
        var parts = transform.components(separatedBy: " ")
        guard parts.count == 12 else { return transform }
        // 3MF transform: r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz
        // Scale X/Y columns: r00, r01, r10, r11, tx, ty (indices 0,1,3,4,9,10)
        let indicesToScale = [0, 1, 3, 4, 9, 10]
        for idx in indicesToScale {
            if let d = Double(parts[idx]) {
                parts[idx] = String(format: "%g", d * factor)
            }
        }
        // Scale Z if zFactor != 1.0: r22 (index 8) and tz (index 11)
        if zFactor != 1.0 {
            if let d = Double(parts[8]) {
                parts[8] = String(format: "%g", d * zFactor)
            }
            if let d = Double(parts[11]) {
                parts[11] = String(format: "%g", d * zFactor)
            }
        }
        return parts.joined(separator: " ")
    }
}