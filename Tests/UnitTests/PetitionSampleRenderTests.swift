import XCTest
import SwiftUI
import PofudukCore
@testable import Pofuduk

/// Renders SAMPLE images of the official-warning UI for the MGM permission petition (Ek 2).
/// Lives in the test target only; the app itself never shows a warning that didn't come from MGM.
/// Every image carries an "ÖRNEK" watermark and a "not a real warning" note.
/// Writes PNGs only when POFUDUK_SAMPLE_DIR is set (CI: TEST_RUNNER_POFUDUK_SAMPLE_DIR).
@MainActor
final class PetitionSampleRenderTests: XCTestCase {
    static let sample: OfficialWarning = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let from = c.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let until = c.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21))!
        return OfficialWarning(
            id: "ornek", level: .orange, hazard: "Kuvvetli yağış (ÖRNEK)",
            description: "ÖRNEK METİN: Bu alanda MGM'nin yayımladığı uyarı açıklaması değiştirilmeden gösterilir.",
            provinces: ["İstanbul"], districts: [], validFrom: from, validUntil: until,
            sourceURL: MGMOfficialPage.warnings)
    }()

    func testRenderPetitionSamples() throws {
        let screens: [(String, AnyView)] = [
            ("ornek-1-ana-ekran-uyari-bandi", AnyView(SampleHomeScreen(warning: Self.sample))),
            ("ornek-2-uyari-detayi", AnyView(SampleDetailScreen(warning: Self.sample)))
        ]
        for (name, view) in screens {
            let renderer = ImageRenderer(content: SampleFrame { view })
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, name)
            XCTAssertEqual(image.size.width, 390)
            if let dir = ProcessInfo.processInfo.environment["POFUDUK_SAMPLE_DIR"], !dir.isEmpty,
               let png = image.pngData() {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}

/// Phone-sized frame with a diagonal watermark and a fixed disclaimer footer.
private struct SampleFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
            Text("ÖRNEK")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.red.opacity(0.13))
                .rotationEffect(.degrees(-30))
            VStack {
                Spacer()
                Text("Bu görüntü dilekçe eki olarak hazırlanmış bir örnektir; gerçek bir MGM uyarısı değildir.")
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
            }
        }
        .frame(width: 390, height: 844)
        .clipped()
    }
}

/// Home screen excerpt: header, real warning banner component, character in warning mode, subtitle.
private struct SampleHomeScreen: View {
    let warning: OfficialWarning

    var body: some View {
        ZStack {
            PofudukGradient.background(for: .rainy, scheme: .light)
            VStack(alignment: .leading, spacing: 16) {
                Label("İstanbul", systemImage: "mappin.and.ellipse")
                    .font(PofudukFont.title).foregroundStyle(PofudukColor.ink)
                    .padding(.top, 56)
                OfficialWarningBanner(warning: warning) {}
                CharacterFigure(appearance: CharacterAppearance(mood: .warning, theme: .rainy), time: CharacterFigure.stillTime)
                    .frame(width: 200, height: 200)
                    .scaleEffect(1.1)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                Text("Dikkat! Bulunduğun bölge için MGM tarafından turuncu seviyede meteorolojik uyarı yayımlanmış. Lütfen resmi uyarının detaylarını incelemeyi unutma.")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(PofudukColor.ink)
                    .padding(18)
                    .background(PofudukColor.surfaceStrong, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Detail screen content (same fields as WarningDetailView, laid out without List for rendering).
private struct SampleDetailScreen: View {
    let warning: OfficialWarning

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(PofudukColor.ink)
        }
        .font(.subheadline)
    }

    var body: some View {
        let validity = WarningDetailView.validity(warning).components(separatedBy: " – ")
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.97)
            VStack(alignment: .leading, spacing: 14) {
                Text("Resmi Uyarılar").font(.headline).frame(maxWidth: .infinity).padding(.top, 60)
                VStack(alignment: .leading, spacing: 12) {
                    Label(warning.level.label, systemImage: warning.level.symbolName)
                        .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PofudukColor.warning(warning.level).opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                    row("Tehlike", warning.hazard)
                    row("Etkilenen bölge", warning.provinces.joined(separator: ", "))
                    row("Başlangıç", validity.first ?? "")
                    row("Bitiş", validity.last ?? "")
                    Text(warning.description).font(.subheadline).foregroundStyle(PofudukColor.ink)
                    Label("Resmi kaynak: MGM", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(PofudukColor.accent)
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                Text("Bu uyarılar Meteoroloji Genel Müdürlüğü'nün resmi kaynağından alınır. Pofuduk'un kendi hava tahminleri resmi uyarı değildir ve hiçbir zaman uyarıya dönüştürülmez.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }
}
