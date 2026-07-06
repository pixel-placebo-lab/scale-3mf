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
    let transformScaled: Bool
}

final class Converter {
    static func scale(input: URL, sae: String, type: FastenerType = .hexHead) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        guard let entry = ConversionTable.entry(forSae: sae, type: type) else {
            throw Scale3MFError.unknownSae(sae, type)
        }

        let (result, transformScaled) = try scale(input: input, factor: entry.scaleFactor)
        return ConversionResult(input: input,
                                output: result,
                                sae: entry.sae,
                                metric: entry.metric,
                                scaleFactor: entry.scaleFactor,
                                transformScaled: transformScaled)
    }

    static func scaleWithFactor(input: URL, factor: Double) throws -> ConversionResult {
        guard input.pathExtension.lowercased() == "3mf" else {
            throw Scale3MFError.not3MF(input)
        }
        let (result, transformScaled) = try scale(input: input, factor: factor)
        return ConversionResult(input: input,
                                output: result,
                                sae: "custom",
                                metric: "custom",
                                scaleFactor: factor,
                                transformScaled: transformScaled)
    }

    private static func scale(input: URL, factor: Double) throws -> (URL, Bool) {
        let data = try Data(contentsOf: input)
        let archive = try Archive(data: data, accessMode: .update)

        guard let modelEntry = archive["3D/3dmodel.model"] else {
            throw Scale3MFError.noModelEntry
        }

        var modelData = Data()
        _ = try archive.extract(modelEntry) { chunk in modelData.append(chunk) }

        let (scaledData, transformScaled) = try scaleModelXML(modelData, factor: factor)

        let stem = input.deletingPathExtension().lastPathComponent
        let outputName = "\(stem)_s\(String(format: "%.3f", factor)).3mf"
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

    private static func scaleModelXML(_ data: Data, factor: Double) throws -> (Data, Bool) {
        let parser = XMLParser(data: data)
        let delegate = ModelXMLScaler(factor: factor)
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
    var output = Data()
    var transformScaled = false
    var currentElement: String?

    init(factor: Double) {
        self.factor = factor
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
            }
        } else if elementName == "item" {
            if let transform = attrs["transform"] {
                attrs["transform"] = scaleTransform(transform)
                transformScaled = true
            }
        }

        var tag = "<\(elementName)"
        for (key, value) in attrs {
            let escaped = value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            tag += " \(key)=\"\(escaped)\""
        }
        tag += ">"
        if let data = tag.data(using: .utf8) {
            output.append(data)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let data = "</\(elementName)>".data(using: .utf8) {
            output.append(data)
        }
        currentElement = nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let data = string.data(using: .utf8) {
            output.append(data)
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        output.append(CDATABlock)
    }

    private func scaleString(_ value: String) -> String {
        guard let d = Double(value) else { return value }
        return String(format: "%g", d * factor)
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
        return parts.joined(separator: " ")
    }
}
