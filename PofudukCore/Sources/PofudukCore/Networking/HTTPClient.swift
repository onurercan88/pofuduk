import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
private let networkLog = Logger(subsystem: "com.pofuduk.app", category: "network")
#endif

public struct HTTPResponse: Sendable {
    public var data: Data
    public var statusCode: Int
    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

/// Minimal HTTP abstraction so providers are testable with canned responses.
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> HTTPResponse
}

public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// One retry after a short pause on transport failures (flaky mobile networks, cold DNS).
    public func get(_ url: URL) async throws -> HTTPResponse {
        do {
            return try await attempt(url)
        } catch {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return try await attempt(url)
        }
    }

    private func attempt(_ url: URL) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: url) { data, response, error in
                if let error {
                    // Never include the URL in errors or logs: it may carry an API key.
                    #if canImport(os)
                    let ns = error as NSError
                    networkLog.error("transport error \(ns.domain, privacy: .public) \(ns.code, privacy: .public) host=\(url.host ?? "-", privacy: .public)")
                    #endif
                    continuation.resume(throwing: WeatherError.network)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: HTTPResponse(data: data ?? Data(), statusCode: status))
            }.resume()
        }
    }
}

extension WeatherError {
    /// Short Turkish explanation for the user. Never claims data that wasn't retrieved.
    public var turkishExplanation: String {
        switch self {
        case .network: return "İnternet bağlantını kontrol edebilirsin."
        case .rateLimited: return "Hava durumu servisi şu an çok yoğun, biraz sonra tekrar deneyeceğim."
        case .missingAPIKey: return "Hava durumu servisine bağlanmak için gerekli ayar eksik."
        case .invalidResponse: return "Hava durumu servisinden anlaşılır bir yanıt alamadım."
        case .outOfForecastRange: return "İstediğin tarih için tahmin henüz yayımlanmadı."
        case .noData: return "Bu konum için hava durumu bilgisi bulunamadı."
        }
    }
}
