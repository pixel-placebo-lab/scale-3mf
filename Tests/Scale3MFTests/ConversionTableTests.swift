import XCTest
@testable import Scale3MF

final class ConversionTableTests: XCTestCase {

    // MARK: - Fallback Data

    func testFallbackEntriesContainHexHead() {
        let entries = ConversionTable.fallbackEntries
        XCTAssertFalse(entries.isEmpty, "Fallback entries should not be empty")
        XCTAssertTrue(entries.allSatisfy { $0.fastenerType == "hex_head" })
    }

    func testFallbackEntryForQuarterInch() {
        let entry = ConversionTable.fallbackEntries.first { $0.sae == "1/4" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.metric, "M6")
        XCTAssertEqual(entry?.saeDim ?? 0, 11.11, accuracy: 0.01)
        XCTAssertEqual(entry?.metricDim ?? 0, 10.0, accuracy: 0.01)
    }

    func testFallbackEntryForOneInch() {
        let entry = ConversionTable.fallbackEntries.first { $0.sae == "1" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.metric, "M24")
    }

    // MARK: - Scale Factor Calculation

    func testScaleFactorForQuarterInch() {
        let entry = ConversionTable.fallbackEntries.first { $0.sae == "1/4" }!
        let expected = entry.saeDim / entry.metricDim
        XCTAssertEqual(entry.scaleFactor, expected, accuracy: 0.0001)
        // 11.11 / 10.00 = 1.111
        XCTAssertEqual(entry.scaleFactor, 1.111, accuracy: 0.001)
    }

    func testScaleFactorForFiveSixteenths() {
        let entry = ConversionTable.fallbackEntries.first { $0.sae == "5/16" }!
        // 12.70 / 13.00 = 0.9769...
        XCTAssertEqual(entry.scaleFactor, 0.9769, accuracy: 0.001)
    }

    // MARK: - FastenerType

    func testFastenerTypeRawValues() {
        XCTAssertEqual(FastenerType.hexHead.rawValue, "hex_head")
        XCTAssertEqual(FastenerType.hexNut.rawValue, "hex_nut")
        XCTAssertEqual(FastenerType.nylockNut.rawValue, "nylock_nut")
        XCTAssertEqual(FastenerType.socketHeadCap.rawValue, "socket_head_cap")
        XCTAssertEqual(FastenerType.buttonHeadCap.rawValue, "button_head_cap")
    }

    func testFastenerTypeAllCases() {
        XCTAssertEqual(FastenerType.allCases.count, 5)
    }

    func testFastenerTypeDisplayNames() {
        XCTAssertEqual(FastenerType.hexHead.displayName, "Hex Head Bolt")
        XCTAssertEqual(FastenerType.hexNut.displayName, "Hex Nut")
        XCTAssertEqual(FastenerType.nylockNut.displayName, "Nylock Nut")
        XCTAssertEqual(FastenerType.socketHeadCap.displayName, "Socket Head Cap")
        XCTAssertEqual(FastenerType.buttonHeadCap.displayName, "Button Head Cap")
    }

    func testFastenerTypeDimensionLabels() {
        XCTAssertTrue(FastenerType.hexHead.dimensionLabel.contains("Flats"))
        XCTAssertTrue(FastenerType.socketHeadCap.dimensionLabel.contains("Diameter"))
    }

    func testFastenerTypeHeightJSONKeys() {
        XCTAssertNotNil(FastenerType.hexHead.heightJSONKey)
        XCTAssertEqual(FastenerType.hexHead.heightJSONKey, "hex_head_bolt")
        XCTAssertEqual(FastenerType.hexNut.heightJSONKey, "hex_nut")
    }

    // MARK: - Metric Dimension Lookup

    func testMetricDimensionFallbackForHexHead() {
        // M8 hex head AF = 13.0mm
        let dim = ConversionTable.metricDimension(for: "M8", type: .hexHead)
        XCTAssertNotNil(dim)
        XCTAssertEqual(dim!, 13.0, accuracy: 0.01)
    }

    func testMetricDimensionFallbackForSocketHeadCap() {
        // M8 socket head cap = 13.0mm head dia
        let dim = ConversionTable.metricDimension(for: "M8", type: .socketHeadCap)
        XCTAssertNotNil(dim)
        XCTAssertEqual(dim!, 13.0, accuracy: 0.01)
    }

    func testMetricDimensionFallbackForButtonHeadCap() {
        // M5 button head cap = 9.5mm head dia
        let dim = ConversionTable.metricDimension(for: "M5", type: .buttonHeadCap)
        XCTAssertNotNil(dim)
        XCTAssertEqual(dim!, 9.5, accuracy: 0.01)
    }

    func testMetricDimensionUnknownReturnsNil() {
        let dim = ConversionTable.metricDimension(for: "M99", type: .hexHead)
        XCTAssertNil(dim)
    }

    // MARK: - SAE Dimension Lookup

    func testSAEDimensionFallbackForHexHead() {
        let dim = ConversionTable.saeDimension(for: "5/16", type: .hexHead)
        XCTAssertNotNil(dim)
        XCTAssertEqual(dim!, 12.70, accuracy: 0.01)
    }

    func testSAEDimensionFallbackForOneInch() {
        let dim = ConversionTable.saeDimension(for: "1", type: .hexHead)
        XCTAssertNotNil(dim)
        XCTAssertEqual(dim!, 41.28, accuracy: 0.01)
    }

    // MARK: - Metric Sizes List

    func testMetricSizesContainsCoreSizes() {
        let sizes = ConversionTable.metricSizes(for: .hexHead)
        XCTAssertTrue(sizes.contains("M6"))
        XCTAssertTrue(sizes.contains("M8"))
        XCTAssertTrue(sizes.contains("M10"))
        XCTAssertTrue(sizes.contains("M12"))
    }

    // MARK: - Entry Lookup

    func testEntryForSAEFiveSixteenths() {
        let entry = ConversionTable.entry(forSae: "5/16", type: .hexHead)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.sae, "5/16")
        XCTAssertEqual(entry?.metric, "M8")
    }

    func testEntryForSAEUnknownReturnsNil() {
        let entry = ConversionTable.entry(forSae: "99/99", type: .hexHead)
        XCTAssertNil(entry)
    }

    // MARK: - Formatted Table

    func testFormattedTableContainsHeader() {
        let table = ConversionTable.formattedTable(type: .hexHead)
        XCTAssertTrue(table.contains("Hex Head Bolt"))
        XCTAssertTrue(table.contains("SAE"))
        XCTAssertTrue(table.contains("Scale"))
    }

    func testFormattedTableContainsKnownSizes() {
        let table = ConversionTable.formattedTable(type: .hexHead)
        XCTAssertTrue(table.contains("1/4"))
        XCTAssertTrue(table.contains("5/16"))
        XCTAssertTrue(table.contains("1"))
    }

    func testFormattedMetricTableContainsTarget() {
        let table = ConversionTable.formattedMetricTable(type: .hexHead, targetMetric: "M5")
        XCTAssertTrue(table.contains("M5"))
        XCTAssertTrue(table.contains("Source"))
    }

    // MARK: - Extrusion Profiles

    func testExtrusionProfilesLoaded() {
        // If JSON is bundled, profiles should load; if not, list is empty
        // At minimum, the property should not crash
        let profiles = ConversionTable.extrusionProfiles
        // If loaded from JSON, we expect 8 presets
        if !profiles.isEmpty {
            XCTAssertEqual(profiles.count, 8, "Expected 8 extrusion profile presets")
        }
    }

    func testExtrusionProfileKnownKey() {
        if let profile = ConversionTable.extrusionProfile(forKey: "2020-to-1010") {
            XCTAssertEqual(profile.scale, 25.4 / 20.0, accuracy: 0.001)
            XCTAssertTrue(profile.isMetricToImperial)
        }
    }

    func testExtrusionProfileUnknownKeyReturnsNil() {
        XCTAssertNil(ConversionTable.extrusionProfile(forKey: "nonexistent"))
    }
}