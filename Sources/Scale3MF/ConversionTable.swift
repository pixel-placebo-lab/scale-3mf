import Foundation

struct SAEEntry: Identifiable, Hashable {
    let id = UUID()
    let sae: String
    let saeDim: Double
    let metric: String
    let metricDim: Double
    var scaleFactor: Double { saeDim / metricDim }
    let fastenerType: String
    let height: FastenerHeight?
}

struct FastenerHeight: Hashable {
    let saeHeightMM: Double
    let metricHeightMM: Double
    let closestMetric: String
}

enum FastenerType: String, CaseIterable, Identifiable, Hashable {
    case hexHead = "hex_head"
    case hexNut = "hex_nut"
    case nylockNut = "nylock_nut"
    case socketHeadCap = "socket_head_cap"
    case buttonHeadCap = "button_head_cap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hexHead: return "Hex Head Bolt"
        case .hexNut: return "Hex Nut"
        case .nylockNut: return "Nylock Nut"
        case .socketHeadCap: return "Socket Head Cap"
        case .buttonHeadCap: return "Button Head Cap"
        }
    }

    var dimensionLabel: String {
        switch self {
        case .hexHead, .hexNut, .nylockNut: return "Across Flats"
        case .socketHeadCap, .buttonHeadCap: return "Head Diameter"
        }
    }

    var heightJSONKey: String? {
        switch self {
        case .hexHead: return "hex_head_bolt"
        case .hexNut: return "hex_nut"
        case .nylockNut: return "nylock_nut"
        case .socketHeadCap: return "socket_head_cap"
        case .buttonHeadCap: return "button_head_cap"
        }
    }
}

struct ConversionTable {
    static let appVersion = "v1.0.0"

    // Fallback hex head data (used if JSON fails to load)
    static let fallbackEntries: [SAEEntry] = [
        SAEEntry(sae: "1/4",  saeDim: 11.11, metric: "M6",  metricDim: 10.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "5/16", saeDim: 12.70, metric: "M8",  metricDim: 13.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "3/8",  saeDim: 14.29, metric: "M10", metricDim: 16.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "7/16", saeDim: 15.88, metric: "M10", metricDim: 16.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "1/2",  saeDim: 19.05, metric: "M12", metricDim: 18.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "9/16", saeDim: 22.23, metric: "M14", metricDim: 21.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "5/8",  saeDim: 23.81, metric: "M16", metricDim: 24.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "3/4",  saeDim: 28.58, metric: "M20", metricDim: 30.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "7/8",  saeDim: 34.93, metric: "M22", metricDim: 34.00, fastenerType: "hex_head", height: nil),
        SAEEntry(sae: "1",    saeDim: 41.28, metric: "M24", metricDim: 36.00, fastenerType: "hex_head", height: nil),
    ]

    private static var loadedEntries: [SAEEntry]?

    static func entries(type: FastenerType = .hexHead) -> [SAEEntry] {
        let all = loadedEntries ?? (loadEntriesFromJSON() ?? fallbackEntries)
        loadedEntries = all
        return all.filter { $0.fastenerType == type.rawValue }
    }

    static func entry(forSae sae: String, type: FastenerType = .hexHead) -> SAEEntry? {
        entries(type: type).first { $0.sae == sae }
    }

    static func types() -> [FastenerType] {
        let all = loadedEntries ?? (loadEntriesFromJSON() ?? fallbackEntries)
        loadedEntries = all
        let present = Set(all.map { $0.fastenerType })
        return FastenerType.allCases.filter { present.contains($0.rawValue) }
    }

    static func saeSizes(for type: FastenerType = .hexHead) -> [String] {
        entries(type: type).map { $0.sae }
    }

    // MARK: - JSON Loading

    static func locateResource(named name: String) -> URL? {
        let fm = FileManager.default
        if let bundle = Bundle.main.resourceURL {
            let bundled = bundle.appendingPathComponent(name)
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        if let exec = Bundle.main.executableURL {
            let sibling = exec.deletingLastPathComponent().appendingPathComponent(name)
            if fm.fileExists(atPath: sibling.path) { return sibling }
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(name)
        if fm.fileExists(atPath: cwd.path) { return cwd }
        return nil
    }

    private static func loadEntriesFromJSON() -> [SAEEntry]? {
        var result: [SAEEntry] = []
        guard let dimURL = locateResource(named: "fastener-dimensions.json"),
              let dimData = try? Data(contentsOf: dimURL),
              let dimJSON = try? JSONSerialization.jsonObject(with: dimData) as? [String: Any] else {
            return nil
        }

        let heights = loadHeightsMap()

        // hex_head → hexHead + hexNut (same AF, different heights)
        if let dict = dimJSON["hex_head"] as? [String: [String: Any]] {
            for (_, v) in dict {
                guard let thread = v["thread"] as? String,
                      let saeDim = v["across_flats_mm"] as? Double else { continue }
                let metric = (v["closest_metric"] as? String) ?? ""
                let metricDim = (v["metric_af_mm"] as? Double) ?? saeDim
                // Hex Head Bolt
                result.append(SAEEntry(
                    sae: thread, saeDim: saeDim, metric: metric, metricDim: metricDim,
                    fastenerType: FastenerType.hexHead.rawValue,
                    height: heights["hex_head_bolt"]?[thread]))
                // Hex Nut (same AF, different height)
                result.append(SAEEntry(
                    sae: thread, saeDim: saeDim, metric: metric, metricDim: metricDim,
                    fastenerType: FastenerType.hexNut.rawValue,
                    height: heights["hex_nut"]?[thread]))
            }
        }

        // nylock_nut
        if let dict = dimJSON["nylock_nut"] as? [String: [String: Any]] {
            for (_, v) in dict {
                guard let thread = v["thread"] as? String,
                      let saeDim = v["across_flats_mm"] as? Double else { continue }
                let metric = (v["closest_metric"] as? String) ?? ""
                let metricDim = (v["metric_af_mm"] as? Double) ?? saeDim
                result.append(SAEEntry(
                    sae: thread, saeDim: saeDim, metric: metric, metricDim: metricDim,
                    fastenerType: FastenerType.nylockNut.rawValue,
                    height: heights["nylock_nut"]?[thread]))
            }
        }

        // socket_head_cap
        if let dict = dimJSON["socket_head_cap"] as? [String: [String: Any]] {
            for (_, v) in dict {
                guard let thread = v["thread"] as? String,
                      let saeDim = v["head_dia_mm"] as? Double else { continue }
                let metric = (v["closest_metric"] as? String) ?? ""
                let metricDim = (v["metric_head_dia_mm"] as? Double) ?? saeDim
                result.append(SAEEntry(
                    sae: thread, saeDim: saeDim, metric: metric, metricDim: metricDim,
                    fastenerType: FastenerType.socketHeadCap.rawValue,
                    height: heights["socket_head_cap"]?[thread]))
            }
        }

        // button_head_cap
        if let dict = dimJSON["button_head_cap"] as? [String: [String: Any]] {
            for (_, v) in dict {
                guard let thread = v["thread"] as? String,
                      let saeDim = v["head_dia_mm"] as? Double else { continue }
                let metric = (v["closest_metric"] as? String) ?? ""
                let metricDim = (v["metric_head_dia_mm"] as? Double) ?? saeDim
                result.append(SAEEntry(
                    sae: thread, saeDim: saeDim, metric: metric, metricDim: metricDim,
                    fastenerType: FastenerType.buttonHeadCap.rawValue,
                    height: heights["button_head_cap"]?[thread]))
            }
        }

        // Filter to SAE sizes only (thread must contain "/")
        result = result.filter { $0.sae.contains("/") || $0.sae == "1" }
        return result.isEmpty ? nil : result
    }

    private static func loadHeightsMap() -> [String: [String: FastenerHeight]] {
        guard let url = locateResource(named: "fastener-heights.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]]
        else { return [:] }

        var map: [String: [String: FastenerHeight]] = [:]
        for (kind, sizes) in json {
            var inner: [String: FastenerHeight] = [:]
            for (size, v) in sizes {
                guard let h = v["height_mm"] as? Double,
                      let cm = v["closest_metric"] as? String,
                      let mh = v["metric_height_mm"] as? Double else { continue }
                inner[size] = FastenerHeight(saeHeightMM: h, metricHeightMM: mh, closestMetric: cm)
            }
            map[kind] = inner
        }
        return map
    }
}
// MARK: - Formatted Table (CLI)
extension ConversionTable {
    static func formattedTable(type: FastenerType = .hexHead) -> String {
        let order = ["1/4", "5/16", "3/8", "7/16", "1/2", "9/16", "5/8", "3/4", "7/8", "1"]
        let rows = entries(type: type).sorted { a, b in
            (order.firstIndex(of: a.sae) ?? 99) < (order.firstIndex(of: b.sae) ?? 99)
        }
        func pad(_ s: String, _ width: Int) -> String {
            if s.count >= width { return s }
            return s + String(repeating: " ", count: width - s.count)
        }
        var lines: [String] = []
        lines.append("\(type.displayName) - Metric to SAE Scaling Table")
        lines.append("\(pad("SAE", 8)) \(pad("SAE(mm)", 10)) \(pad("Metric", 8)) \(pad("Metric(mm)", 12)) Scale")
        for e in rows {
            lines.append("\(pad(e.sae, 8)) \(String(format: "%10.2f", e.saeDim))  \(pad(e.metric, 8)) \(String(format: "%12.2f", e.metricDim))  \(String(format: "%10.4f", e.scaleFactor))")
        }
        return lines.joined(separator: "\n")
    }
}
