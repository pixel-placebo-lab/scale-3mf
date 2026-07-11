import SwiftUI

struct DropResult: Identifiable {
    let id = UUID()
    let inputName: String
    let outputName: String
    let success: Bool
    let message: String
}

enum SourceType: String, CaseIterable, Identifiable {
    case metric
    case sae
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .sae: return "SAE"
        }
    }
}

enum TargetType: String, CaseIterable, Identifiable {
    case sae
    case metric
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sae: return "SAE"
        case .metric: return "Metric"
        }
    }
}

enum ScaleMode: String, CaseIterable, Identifiable {
    case simple, advanced, profile
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        case .profile: return "8020"
        }
    }
}

struct ContentView: View {
    @State private var selectedFastener: FastenerType = .hexHead
    @State private var selectedSAE: String = "1/4"

    // Mode
    @State private var scaleMode: ScaleMode = .simple

    // Advanced mode state
    @State private var selectedSourceType: SourceType = .metric
    @State private var selectedSourceMetric: String = "M8"
    @State private var selectedSourceSAE: String = "1/4"
    @State private var selectedTargetType: TargetType = .sae
    @State private var selectedTargetSAE: String = "3/8"
    @State private var selectedTargetMetric: String = "M10"

    // 8020 profile mode state
    @State private var selectedProfileKey: String = "2020-to-1010"

    @State private var results: [DropResult] = []
    @State private var isTargeted = false
    @State private var statusText = "Drop a .3MF file to scale"
    @State private var zScaleEnabled = false
    @State private var zScaleFactor: Double = 1.0

    private var saeSizes: [String] {
        ConversionTable.saeSizes(for: selectedFastener)
    }

    private var metricSizes: [String] {
        ConversionTable.metricSizes(for: selectedFastener)
    }

    var selectedEntry: SAEEntry? {
        ConversionTable.entry(forSae: selectedSAE, type: selectedFastener)
    }

    // MARK: - Advanced dimension lookups

    var advancedSourceDim: Double? {
        switch selectedSourceType {
        case .metric:
            return ConversionTable.metricDimension(for: selectedSourceMetric, type: selectedFastener)
        case .sae:
            return ConversionTable.saeDimension(for: selectedSourceSAE, type: selectedFastener)
        }
    }

    var advancedTargetDim: Double? {
        switch selectedTargetType {
        case .sae:
            return ConversionTable.saeDimension(for: selectedTargetSAE, type: selectedFastener)
        case .metric:
            return ConversionTable.metricDimension(for: selectedTargetMetric, type: selectedFastener)
        }
    }

    var advancedScale: Double? {
        guard let s = advancedSourceDim, s > 0,
              let t = advancedTargetDim, t > 0 else { return nil }
        return t / s
    }

    var advancedScaleValid: Bool { advancedScale != nil }

    var advancedSourceLabel: String {
        switch selectedSourceType {
        case .metric: return selectedSourceMetric
        case .sae: return selectedSourceSAE
        }
    }

    var advancedTargetLabel: String {
        switch selectedTargetType {
        case .sae: return selectedTargetSAE
        case .metric: return selectedTargetMetric
        }
    }

    // MARK: - 8020 profile lookups

    var selectedProfile: ConversionTable.ExtrusionProfile? {
        ConversionTable.extrusionProfile(forKey: selectedProfileKey)
    }

    var profileSlotAfterScale: Double? {
        guard let p = selectedProfile else { return nil }
        return p.sourceSlot * p.scale
    }

    var profileSlotMismatch: Double? {
        guard let p = selectedProfile, let after = profileSlotAfterScale else { return nil }
        return after - p.targetSlot
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("Scale3MF 🦞")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Universal 3MF Scaling")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            dropZone
                .frame(maxWidth: .infinity, minHeight: 120)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Fastener type (hidden in profile mode)
                    if scaleMode != .profile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fastener Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Fastener Type", selection: $selectedFastener) {
                                ForEach(prioritizedTypes()) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: selectedFastener) { _ in
                                if !saeSizes.contains(selectedSAE), let first = saeSizes.first {
                                    selectedSAE = first
                                }
                                if !saeSizes.contains(selectedSourceSAE), let first = saeSizes.first {
                                    selectedSourceSAE = first
                                }
                                if !saeSizes.contains(selectedTargetSAE), let first = saeSizes.first {
                                    selectedTargetSAE = first
                                }
                                if !metricSizes.contains(selectedSourceMetric), let first = metricSizes.first {
                                    selectedSourceMetric = first
                                }
                                if !metricSizes.contains(selectedTargetMetric), let first = metricSizes.first {
                                    selectedTargetMetric = first
                                }
                            }
                        }
                    }

                    // Mode picker (segmented)
                    Picker("Mode", selection: $scaleMode) {
                        ForEach(ScaleMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    switch scaleMode {
                    case .simple:
                        simpleControls
                    case .advanced:
                        advancedControls
                    case .profile:
                        profileControls
                    }

                    // Z Scale control
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Z Scale", isOn: $zScaleEnabled)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if zScaleEnabled {
                            HStack {
                                Text("Z Factor")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Slider(value: $zScaleFactor, in: 0.1...3.0, step: 0.001)
                                Text(String(format: "%.3f", zScaleFactor))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            Button(action: selectFileAndScale) {
                Text("Scale")
                    .frame(minWidth: 120)
            }
            .disabled(scaleMode == .advanced ? !advancedScaleValid : (scaleMode == .profile ? selectedProfile == nil : selectedEntry == nil))

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !results.isEmpty {
                List {
                    ForEach(results.reversed()) { result in
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.inputName)
                                    .lineLimit(1)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 100)
            }

            Spacer()

            Text("Scale3MF \(ConversionTable.appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .frame(width: 400, height: 740)
    }

    // MARK: - Simple controls

    private var simpleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Target SAE Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("SAE Size", selection: $selectedSAE) {
                    ForEach(saeSizes, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            if let entry = selectedEntry {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From: \(entry.metric) (\(String(format: "%.2f", entry.metricDim)) mm)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("To: \(entry.sae) (\(String(format: "%.2f", entry.saeDim)) mm)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Scale X/Y")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.4f", entry.scaleFactor))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(entry.scaleFactor < 1.0 ? .orange : .green)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            }
        }
    }

    // MARK: - Advanced controls

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source type toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Source Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Source Type", selection: $selectedSourceType) {
                    ForEach(SourceType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Source size
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSourceType == .metric ? "Source Metric Size" : "Source SAE Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if selectedSourceType == .metric {
                    Picker("Source Metric", selection: $selectedSourceMetric) {
                        ForEach(metricSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                } else {
                    Picker("Source SAE", selection: $selectedSourceSAE) {
                        ForEach(saeSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            // Target type toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Target Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Target Type", selection: $selectedTargetType) {
                    ForEach(TargetType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Target size
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTargetType == .sae ? "Target SAE Size" : "Target Metric Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if selectedTargetType == .sae {
                    Picker("Target SAE Size", selection: $selectedTargetSAE) {
                        ForEach(saeSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                } else {
                    Picker("Target Metric Size", selection: $selectedTargetMetric) {
                        ForEach(metricSizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            // Scale summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source: \(advancedSourceLabel) (\(advancedSourceDim.map { String(format: "%.2f", $0) } ?? "—") mm)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Target: \(advancedTargetLabel) (\(advancedTargetDim.map { String(format: "%.2f", $0) } ?? "—") mm)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Scale X/Y")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let scale = advancedScale {
                        Text(String(format: "%.4f", scale))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(scale < 1.0 ? .orange : .green)
                    } else {
                        Text("—")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
    }

    // MARK: - 8020 Profile controls

    private var profileControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile Preset")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Profile", selection: $selectedProfileKey) {
                    ForEach(ConversionTable.extrusionProfiles, id: \.key) { item in
                        Text(item.profile.name).tag(item.key)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            if let p = selectedProfile {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source: \(p.sourceLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Target: \(p.targetLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body Scale")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.4f", p.scale))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(p.scale < 1.0 ? .orange : .green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Δ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%+.2f%%", (p.scale - 1) * 100))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(p.scale < 1.0 ? .orange : .green)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))

                // T-slot analysis
                if let after = profileSlotAfterScale, let mismatch = profileSlotMismatch {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("T-slot after scale: \(String(format: "%.2f", after))mm (target: \(String(format: "%.2f", p.targetSlot))mm)")
                            .font(.caption)
                            .foregroundColor(abs(mismatch) > 0.1 ? .orange : .green)
                        if abs(mismatch) > 0.1 {
                            Text("⚠ T-slot \(mismatch > 0 ? "oversized" : "undersized") by \(String(format: "%.2f", abs(mismatch)))mm")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Uniform scaling can't fix slots. Design in OpenSCAD with separate slot params for perfect fit.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("✓ T-slot within tolerance")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                }
            }
        }
    }

    // MARK: - Helpers

    private func prioritizedTypes() -> [FastenerType] {
        let priority: [FastenerType] = [.hexHead, .hexNut, .nylockNut, .socketHeadCap, .buttonHeadCap]
        let available = Set(ConversionTable.types().map { $0 })
        return priority.filter { available.contains($0) }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .blue : .secondary)
                .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.05)))

            VStack(spacing: 8) {
                Image(systemName: "cube.box")
                    .font(.system(size: 40))
                    .foregroundColor(isTargeted ? .blue : .secondary)
                Text("Drop .3MF files here")
                    .font(.headline)
                Text(zScaleEnabled ? "Z axis scaled by \(String(format: "%.3f", zScaleFactor))" : "Z axis not scaled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            handleProviders(providers)
            return true
        }
    }

    private func handleProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    self.scaleFile(url)
                }
            }
        }
    }

    private func selectFileAndScale() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["3mf"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.scaleFile(url)
            }
        }
    }

    private func scaleFile(_ url: URL) {
        let zf = zScaleEnabled ? zScaleFactor : 1.0
        do {
            let result: ConversionResult
            switch scaleMode {
            case .simple:
                guard let entry = selectedEntry else { return }
                result = try Converter.scale(input: url, sae: entry.sae, type: selectedFastener, zFactor: zf)
            case .advanced:
                switch (selectedSourceType, selectedTargetType) {
                case (.metric, .sae):
                    result = try Converter.scaleAdvancedMetricToSAE(
                        input: url, sourceMetric: selectedSourceMetric,
                        sae: selectedTargetSAE, type: selectedFastener, zFactor: zf)
                case (.metric, .metric):
                    result = try Converter.scaleAdvancedMetricToMetric(
                        input: url, sourceMetric: selectedSourceMetric,
                        targetMetric: selectedTargetMetric, type: selectedFastener, zFactor: zf)
                case (.sae, .metric):
                    result = try Converter.scaleAdvancedSAEToMetric(
                        input: url, saeSource: selectedSourceSAE,
                        targetMetric: selectedTargetMetric, type: selectedFastener, zFactor: zf)
                case (.sae, .sae):
                    result = try Converter.scaleAdvancedSAEToSAE(
                        input: url, saeSource: selectedSourceSAE,
                        saeTarget: selectedTargetSAE, type: selectedFastener, zFactor: zf)
                }
            case .profile:
                result = try Converter.scaleProfile(input: url, presetKey: selectedProfileKey, zFactor: zf)
            }

            var msg = "\(result.metric) → \(result.sae) × \(String(format: "%.4f", result.scaleFactor))"
            if zf != 1.0 {
                msg += " Z: \(String(format: "%.4f", zf))"
            }
            msg += " → \(result.output.lastPathComponent)"
            results.append(DropResult(inputName: url.lastPathComponent, outputName: result.output.lastPathComponent, success: true, message: msg))
            statusText = "✓ \(result.metric) → \(result.sae) × \(String(format: "%.3f", result.scaleFactor)) → \(result.output.lastPathComponent)"
        } catch {
            results.append(DropResult(inputName: url.lastPathComponent, outputName: "", success: false, message: error.localizedDescription))
            statusText = "✗ \(error.localizedDescription)"
        }
    }
}