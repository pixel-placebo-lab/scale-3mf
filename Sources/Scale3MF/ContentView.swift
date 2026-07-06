import SwiftUI

struct DropResult: Identifiable {
    let id = UUID()
    let inputName: String
    let outputName: String
    let success: Bool
    let message: String
}

struct ContentView: View {
    @State private var selectedFastener: FastenerType = .hexHead
    @State private var selectedSAE: String = "1/4"
    @State private var results: [DropResult] = []
    @State private var isTargeted = false
    @State private var statusText = "Drop a .3MF file to scale"
    @State private var zScaleEnabled = false
    @State private var zScaleFactor: Double = 1.0

    private var saeSizes: [String] {
        ConversionTable.saeSizes(for: selectedFastener)
    }

    var selectedEntry: SAEEntry? {
        ConversionTable.entry(forSae: selectedSAE, type: selectedFastener)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 2) {
                Text("Scale3MF 🦞")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Metric → SAE 3MF Scaling")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            // Drop zone
            dropZone
                .frame(maxWidth: .infinity, minHeight: 140)

            // Controls
            VStack(alignment: .leading, spacing: 12) {
                // Fastener type - dropdown, not segmented
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
                    }
                }

                // SAE size - dropdown, not segmented
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

                // Scale info
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

            // Scale button
            Button(action: selectFileAndScale) {
                Text("Scale")
                    .frame(minWidth: 120)
            }
            .disabled(selectedEntry == nil)

            // Status
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Results list
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
                .frame(minHeight: 60, maxHeight: 120)
            }

            Spacer()

            // Version
            Text("Scale3MF \(ConversionTable.appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .frame(width: 380, height: 620)
    }

    private func prioritizedTypes() -> [FastenerType] {
        // Hex Head first, then Hex Nut, Nylock, then the rest
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
        guard let entry = selectedEntry else { return }
        let zf = zScaleEnabled ? zScaleFactor : 1.0
        do {
            let result = try Converter.scale(input: url, sae: entry.sae, type: selectedFastener, zFactor: zf)
            var msg = "Scaled by \(String(format: "%.4f", result.scaleFactor))"
            if zf != 1.0 {
                msg += " Z: \(String(format: "%.4f", zf))"
            }
            msg += " → \(result.output.lastPathComponent)"
            results.append(DropResult(inputName: url.lastPathComponent, outputName: result.output.lastPathComponent, success: true, message: msg))
            statusText = "✓ \(result.output.lastPathComponent)"
        } catch {
            results.append(DropResult(inputName: url.lastPathComponent, outputName: "", success: false, message: error.localizedDescription))
            statusText = "✗ \(error.localizedDescription)"
        }
    }
}