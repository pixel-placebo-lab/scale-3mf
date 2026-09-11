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

    // MARK: - Matrix Correctness Tests (Sep 2026 review fixes)

    /// Extract the first transform="..." attribute as 12 doubles (row-major
    /// 4×3: m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32).
    private func firstTransformValues(in xml: String) -> [Double] {
        guard let open = xml.range(of: "transform=\""),
              let close = xml.range(of: "\"", range: open.upperBound..<xml.endIndex)
        else { return [] }
        return xml[open.upperBound..<close.lowerBound]
            .split(separator: " ")
            .compactMap { Double($0) }
    }

    /// Extract an <object id="N"> ... </object> block.
    private func objectBlock(_ id: String, in xml: String) -> String {
        let start = xml.range(of: "<object id=\"\(id)\"")!
        let end = xml.range(of: "</object>", range: start.upperBound..<xml.endIndex)!
        return String(xml[start.lowerBound..<end.upperBound])
    }

    private func assertMatrix(_ actual: [Double], _ expected: [Double],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, 12, "transform must have 12 values", file: file, line: line)
        guard actual.count == 12, expected.count == 12 else { return }
        for i in 0..<12 {
            XCTAssertEqual(actual[i], expected[i], accuracy: 0.0001,
                           "matrix element \(i): \(actual[i]) != \(expected[i])",
                           file: file, line: line)
        }
    }

    /// X/Y scaling of a tilted (45° about Y) transform must scale the whole
    /// matrix as S·M — m20 included. The old code left m20/m21 unscaled,
    /// shearing rotated objects.
    func testXYScaleOfRotatedTransformAppliesWorldScale() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices><vertex x="0" y="0" z="0"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="0.7071 0 0.7071 0 1 0 -0.7071 0 0.7071 10 20 30"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        // Column scaling: col0 (idx 0,3,6,9) ×2, col1 (1,4,7,10) ×2, col2 ×1
        assertMatrix(firstTransformValues(in: outputXML),
                     [1.4142, 0, 0.7071,
                      0, 2, 0,
                      -1.4142, 0, 0.7071,
                      20, 40, 30])
    }

    /// Z scaling of a tilted (45° about X) transform must scale the whole Z
    /// column (m02/m12/m22/m32). The old code scaled only m22/m32 → shear.
    func testZScaleOfRotatedTransformScalesFullZColumn() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices><vertex x="0" y="0" z="0"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 0.7071 -0.7071 0 0.7071 0.7071 10 20 30"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 1.0, zFactor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        assertMatrix(firstTransformValues(in: outputXML),
                     [1, 0, 0,
                      0, 0.7071, -1.4142,
                      0, 0.7071, 1.4142,
                      10, 20, 60])
    }

    /// A file with one transform-placed object and one vertex-placed object
    /// must scale BOTH: the transform matrix for the first, the vertices of
    /// the second (and NOT the first — no double scaling).
    func testMixedObjectsBothScaled() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices><vertex x="10" y="10" z="10"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
            <object id="2" type="model">
              <mesh>
                <vertices><vertex x="10" y="10" z="10"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1 0 0 0 1 0 0 0 1 5 5 5"/>
            <item objectid="2"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        // Object 1 scaled through its matrix (translation included)
        assertMatrix(firstTransformValues(in: outputXML),
                     [2, 0, 0, 0, 2, 0, 0, 0, 1, 10, 10, 5])
        // Object 1's vertices must NOT be scaled (no double scaling)
        let obj1 = objectBlock("1", in: outputXML)
        XCTAssertTrue(obj1.contains("x=\"10\""), "transform-covered vertices untouched. Got: \(obj1)")
        // Object 2 scaled via its vertices
        let obj2 = objectBlock("2", in: outputXML)
        XCTAssertTrue(obj2.contains("x=\"20\""), "vertex-placed object must scale. Got: \(obj2)")
        XCTAssertTrue(obj2.contains("y=\"20\""), "vertex-placed object must scale Y. Got: \(obj2)")
        XCTAssertTrue(obj2.contains("z=\"10\""), "Z untouched at zFactor=1. Got: \(obj2)")
    }

    /// Vertex x/y/z attributes parsed by name: reordered attributes and
    /// extra attributes scale in place, preserving order and extras.
    func testReorderedVertexAttributesAreScaled() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>
                  <vertex z="3" y="2" x="1" p1="0.5"/>
                  <vertex y="5" x="4" z="6"/>
                </vertices>
                <triangles><triangle v1="0" v2="1" v3="0"/></triangles>
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
        XCTAssertTrue(outputXML.contains("<vertex z=\"3\" y=\"4\" x=\"2\" p1=\"0.5\"/>"),
                      "Reordered attrs scale in place, preserving order + extras. Got: \(outputXML)")
        XCTAssertTrue(outputXML.contains("<vertex y=\"10\" x=\"8\" z=\"6\"/>"),
                      "Second reordered vertex scales. Got: \(outputXML)")
    }

    /// Scientific notation (1e0, 1e1, …) must scale in transforms AND in
    /// vertices of vertex-placed objects — parity with the Python CLI.
    func testScientificNotationInTransformAndVertices() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices><vertex x="1e0" y="1e0" z="1e0"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
            <object id="2" type="model">
              <mesh>
                <vertices><vertex x="1e0" y="2e0" z="3e0"/></vertices>
                <triangles><triangle v1="0" v2="0" v3="0"/></triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" transform="1e0 0 0 0 1e0 0 0 0 1e0 1e1 2e1 3e1"/>
            <item objectid="2"/>
          </build>
        </model>
        """
        let inputURL = try makeTest3MF(modelXML: xml)
        defer { cleanup(inputURL) }

        let result = try Converter.scaleWithFactor(input: inputURL, factor: 2.0)
        defer { cleanup(result.output) }

        let outputXML = try readModelXML(from: result.output)
        // Transform with scientific notation scales
        assertMatrix(firstTransformValues(in: outputXML),
                     [2, 0, 0, 0, 2, 0, 0, 0, 1, 20, 40, 30])
        // Vertices with scientific notation scale in the uncovered object
        let obj2 = objectBlock("2", in: outputXML)
        XCTAssertTrue(obj2.contains("<vertex x=\"2\" y=\"4\" z=\"3\"/>"),
                      "Sci-notation vertices must scale. Got: \(obj2)")
        // Covered object's vertices stay untouched
        let obj1 = objectBlock("1", in: outputXML)
        XCTAssertTrue(obj1.contains("x=\"1e0\""), "Covered vertices untouched. Got: \(obj1)")
    }
}