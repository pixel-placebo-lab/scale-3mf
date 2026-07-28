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
    static let appVersion = "v1.3.0"

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

    // Source metric sizes offered in Advanced mode (filtered by JSON availability when possible)
    static let baseMetricSizes = ["M3", "M4", "M5", "M6", "M8", "M10", "M12", "M14", "M16", "M20", "M22", "M24"]

    // MARK: - 8020 Extrusion Profile Data
    // Loaded from extrusion-profiles.json (bundled or sibling to executable) at first use.
    struct ExtrusionProfile {
        let name: String          // human-readable label
        let sourceLabel: String   // e.g. "20×20mm, slot 8mm"
        let targetLabel: String   // e.g. "1.00×1.00\", slot 0.250\""
        let scale: Double         // body scale factor
        let sourceSlot: Double    // mm
        let targetSlot: Double    // mm
        let isMetricToImperial: Bool
    }

    private static var loadedExtrusionProfiles: [(key: String, profile: ExtrusionProfile)]?

    static var extrusionProfiles: [(key: String, profile: ExtrusionProfile)] {
        if let cached = loadedExtrusionProfiles { return cached }
        let loaded = loadExtrusionProfilesFromJSON() ?? []
        loadedExtrusionProfiles = loaded
        return loaded
    }

    static func extrusionProfile(forKey key: String) -> ExtrusionProfile? {
        extrusionProfiles.first { $0.key == key }?.profile
    }

    private static func loadExtrusionProfilesFromJSON() -> [(key: String, profile: ExtrusionProfile)]? {
        guard let url = locateResource(named: "extrusion-profiles.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["profiles"] as? [[String: Any]] else {
            return nil
        }

        var result: [(key: String, profile: ExtrusionProfile)] = []
        for p in profiles {
            guard let key = p["key"] as? String,
                  let name = p["name"] as? String,
                  let sourceLabel = p["sourceLabel"] as? String,
                  let targetLabel = p["targetLabel"] as? String,
                  let scale = p["scale"] as? Double,
                  let sourceSlot = p["sourceSlot"] as? Double,
                  let targetSlot = p["targetSlot"] as? Double,
                  let isMetricToImperial = p["isMetricToImperial"] as? Bool else {
                continue
            }
            result.append((key, ExtrusionProfile(
                name: name,
                sourceLabel: sourceLabel,
                targetLabel: targetLabel,
                scale: scale,
                sourceSlot: sourceSlot,
                targetSlot: targetSlot,
                isMetricToImperial: isMetricToImperial)))
        }
        return result.isEmpty ? nil : result
    }

    private static var loadedEntries: [SAEEntry]?
    private static var dimensionsJSON: [String: [String: [String: Any]]]?

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

    // MARK: - Metric dimension lookups (used by Advanced mode)

    static func metricSizes(for type: FastenerType = .hexHead) -> [String] {
        // Always return the full list — metricDimension() handles JSON lookup + fallback
        return baseMetricSizes
    }

    static func metricDimension(for size: String, type: FastenerType = .hexHead) -> Double? {
        // Ensure JSON is loaded
        if dimensionsJSON == nil { _ = entries(type: type) }
        let lower = size.lowercased()
        let dimKey = (type == .hexHead || type == .hexNut || type == .nylockNut) ? "across_flats_mm" : "head_dia_mm"
        if let dict = dimensionsJSON?[type.rawValue],
           let entry = dict[lower] ?? dict[size],
           let dim = entry[dimKey] as? Double, dim > 0 {
            return dim
        }
        return fallbackMetricDimension(for: size, type: type)
    }

    static func saeDimension(for size: String, type: FastenerType = .hexHead) -> Double? {
        // Ensure JSON is loaded
        if dimensionsJSON == nil { _ = entries(type: type) }
        let dimKey = (type == .hexHead || type == .hexNut || type == .nylockNut) ? "across_flats_mm" : "head_dia_mm"
        if let dict = dimensionsJSON?[type.rawValue] {
            for (_, entry) in dict {
                if let thread = entry["thread"] as? String, thread == size,
                   let dim = entry[dimKey] as? Double, dim > 0 {
                    return dim
                }
            }
        }
        // Fallback to hardcoded hex head table
        if type == .hexHead || type == .hexNut {
            return fallbackEntries.first { $0.sae == size }?.saeDim
        }
        return nil
    }

    private static func fallbackMetricDimension(for size: String, type: FastenerType) -> Double? {
        // Hardcoded fallbacks for ALL metric sizes (ISO standards)
        // Used when JSON isn't loaded yet or size is missing from JSON
        let upper = size.uppercased()
        let isAF = (type == .hexHead || type == .hexNut || type == .nylockNut)
        let isSocket = (type == .socketHeadCap)
        let isButton = (type == .buttonHeadCap)
        
        let afDims: [String: Double] = [
            "M3": 5.5, "M4": 7.0, "M5": 8.0, "M6": 10.0, "M8": 13.0,
            "M10": 16.0, "M12": 18.0, "M14": 21.0, "M16": 24.0,
            "M20": 30.0, "M22": 34.0, "M24": 36.0
        ]
        let socketDims: [String: Double] = [
            "M3": 5.5, "M4": 7.0, "M5": 8.5, "M6": 10.0, "M8": 13.0,
            "M10": 16.0, "M12": 18.0, "M14": 21.0, "M16": 24.0, "M20": 30.0
        ]
        let buttonDims: [String: Double] = [
            "M3": 5.7, "M4": 7.6, "M5": 9.5, "M6": 10.5, "M8": 14.0, "M10": 17.5
        ]
        
        if isAF { return afDims[upper] }
        if isSocket { return socketDims[upper] }
        if isButton { return buttonDims[upper] }
        return nil
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

        // Store raw dimensions for metric→metric / advanced lookups.
        dimensionsJSON = dimJSON as? [String: [String: [String: Any]]]

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

    static func formattedMetricTable(type: FastenerType = .hexHead, targetMetric: String = "M5") -> String {
        let sizes = metricSizes(for: type)
        guard let targetDim = metricDimension(for: targetMetric, type: type) else {
            return "Target metric \(targetMetric) not found for \(type.displayName)"
        }
        func pad(_ s: String, _ width: Int) -> String {
            if s.count >= width { return s }
            return s + String(repeating: " ", count: width - s.count)
        }
        var lines: [String] = []
        lines.append("\(type.displayName) - Metric → Metric Scaling Table (target: \(targetMetric))")
        lines.append("\(pad("Source", 8)) \(pad("Source(mm)", 12)) \(pad("Target", 8)) \(pad("Target(mm)", 12)) Scale")
        for src in sizes {
            guard let srcDim = metricDimension(for: src, type: type) else { continue }
            let scale = targetDim / srcDim
            lines.append("\(pad(src, 8)) \(String(format: "%12.2f", srcDim))  \(pad(targetMetric, 8)) \(String(format: "%12.2f", targetDim))  \(String(format: "%10.4f", scale))")
        }
        return lines.joined(separator: "\n")
    }
}
