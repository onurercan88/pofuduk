import XCTest
import SwiftUI
@testable import Pofuduk

/// Renders the app icon PNG when POFUDUK_ICON_OUTPUT is set (CI passes it via TEST_RUNNER_POFUDUK_ICON_OUTPUT).
@MainActor
final class AppIconRenderTests: XCTestCase {
    func testRenderAppIcon() throws {
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 1024, height: 1024))

        // App Store icons must be opaque (no alpha channel).
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        XCTAssertFalse(png.isEmpty)
        if let path = ProcessInfo.processInfo.environment["POFUDUK_ICON_OUTPUT"], !path.isEmpty {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
