import XCTest
import ZIPFoundation
@testable import Scale3MF

final class ConverterTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal 3MF ZIP archive in a temp file with the given model XML.
    private func makeTest3MF(modelXML: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("test_\(UUID().uuidString).3mf")
        let archive = try Archive(data: Data(), accessMode: .create)
        let xmlData = modelXML.data(using: .utf8)!
        try archive.addEntry(with: "3D/3dmodel.model", type: .file,
            uncompressedSize: Int64(xmlData.count), modificationDate: Date(),
            compressionMethod: .deflate,
            provider: { pos, size in
                let end = pos + Int64(size)
                return xmlData.subdata(in: Int(pos)..<Int(end))
            })
        // Add minimal content types file required by 3MF spec
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="3mf" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """.data(using: .utf8)!
        try archive.addEntry(with: "[Content_Types].xml", type: .file,
            uncompressedSize: Int64(contentTypes.count), modificationDate: Date(),
            compressionMethod: .deflate,
            provider: { pos, size in
                let end = pos + Int64(size)
                return contentTypes.subdata(in: Int(pos)..<Int(end))
            })
        guard let data = archive.data else {
            throw Scale3MFError.archiveFailed("Could not create test archive")
        }
        try data.write(to: url)
        return url
    }

    /// Read the model XML from a 3MF file.
    private func readModelXML(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let archive = try Archive(data: data, accessMode: .read)
        let entry = archive.filter { $0.path.hasSuffix(".model") }.first!
        var modelData = Data()
        _ = try archive.extract(entry) { chunk in modelData.append(chunk) }
        return String(data: modelData, encoding: .utf8) ?? ""
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Transform Scaling Tests

    func testScaleWithFactorPreservesTransformStructure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="10" y="20" z="30"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)

        // Transform should be scaled: r00, r01, r10, r11, tx, ty *= 2.0
        XCTAssertTrue(outputXML.contains("transform=\"2 0 0 0 2 0 0 0 1 0 0 0\""),
                       "Transform should have r00=2, r11=2, rest unchanged. Got: \(outputXML)")
    }

    func testScaleWithFactorScalesTransformTranslation() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="0" y="0" z="0"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 1 5 10 15"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 0.5)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)

        // tx=5*0.5=2.5, ty=10*0.5=5, tz=15 (untouched when zFactor=1.0)
        XCTAssertTrue(outputXML.contains("2.5 5 15"),
                       "Translation should be scaled by 0.5. Got: \(outputXML)")
    }

    func testScaleWithZFactorScalesZComponents() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="0" y="0" z="0"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 2 4 8 16"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.0, zFactor: 0.5)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)

        // r22=2*0.5=1, tz=16*0.5=8 (tx=4, ty=8 unchanged since factor=1.0)
        XCTAssertTrue(outputXML.contains("1 4 8"),
                       "Z components should be scaled by 0.5. Got: \(outputXML)")
    }

    // MARK: - Vertex Scaling Tests

    func testScaleWithFactorScalesVerticesWhenNoTransform() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="10" y="20" z="30"/>
                  <vertex x="5" y="15" z="25"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="1" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)

        // Vertices should be scaled: x*=2, y*=2, z unchanged
        XCTAssertTrue(outputXML.contains("x=\"20\"") || outputXML.contains("x=\"20."),
                       "Vertex x should be 20 (10*2). Got: \(outputXML)")
        XCTAssertTrue(outputXML.contains("y=\"40\"") || outputXML.contains("y=\"40."),
                       "Vertex y should be 40 (20*2). Got: \(outputXML)")
        // Z should NOT be scaled when zFactor=1.0
        XCTAssertTrue(outputXML.contains("z=\"30\"") || outputXML.contains("z=\"30."),
                       "Vertex z should remain 30. Got: \(outputXML)")
    }

    func testScaleWithZFactorScalesVertexZ() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="10" y="20" z="40"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.0, zFactor: 0.25)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)

        // Z should be 40*0.25=10
        XCTAssertTrue(outputXML.contains("z=\"10\"") || outputXML.contains("z=\"10."),
                       "Vertex z should be 10 (40*0.25). Got: \(outputXML)")
    }

    // MARK: - XML Preservation Tests

    func testScalePreservesXMLComments() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Custom comment -->
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="10" y="10" z="10"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.5)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        XCTAssertTrue(outputXML.contains("Custom comment"),
                       "XML comments should be preserved. Got: \(outputXML)")
    }

    func testScalePreservesSelfClosingTags() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex x="10" y="10" z="10"/>
                </vertices>
                <triangles>
                  <triangle v1="0" v2="0" v3="0"/>
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        // vertex should remain self-closing
        XCTAssertTrue(outputXML.contains("/>"),
                       "Self-closing tags should be preserved. Got: \(outputXML)")
        XCTAssertFalse(outputXML.contains("</vertex>"),
                       "Should not expand self-closing vertex tags. Got: \(outputXML)")
    }

    // MARK: - Error Handling Tests

    func testScaleRejectsNon3MFFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("test.txt")
        try "hello".data(using: .utf8)!.write(to: url)
        defer { cleanup(url) }

        XCTAssertThrowsError(try Converter.scaleWithFactor(input: url, factor: 1.0)) { error in
            guard case Scale3MFError.not3MF = error else {
                XCTFail("Expected not3MF error, got: \(error)")
                return
            }
        }
    }

    func testScaleWithUnknownSAEThrows() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources><object id="1" type="model"><mesh><vertices><vertex x="1" y="1" z="1"/></vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object></resources>
          <build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/></build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        XCTAssertThrowsError(try Converter.scale(input: inputURL, sae: "99/99")) { error in
            guard case Scale3MFError.unknownSae = error else {
                XCTFail("Expected unknownSae error, got: \(error)")
                return
            }
        }
    }

    // MARK: - Result Metadata Tests

    func testConversionResultContainsCorrectFactor() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources><object id="1" type="model"><mesh><vertices><vertex x="1" y="1" z="1"/></vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object></resources>
          <build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/></build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.234)
        defer { cleanup(result.output) }

        XCTAssertEqual(result.scaleFactor, 1.234, accuracy: 0.0001)
        XCTAssertEqual(result.zScaleFactor, 1.0, accuracy: 0.0001)
        XCTAssertTrue(result.transformScaled)
    }

    func testConversionResultOutputFilenameContainsFactor() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources><object id="1" type="model"><mesh><vertices><vertex x="1" y="1" z="1"/></vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object></resources>
          <build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/></build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 0.977)
        defer { cleanup(result.output) }

        XCTAssertTrue(result.output.lastPathComponent.contains("0.977"),
                       "Output filename should contain the scale factor. Got: \(result.output.lastPathComponent)")
        XCTAssertTrue(result.output.lastPathComponent.hasSuffix(".3mf"))
    }
}