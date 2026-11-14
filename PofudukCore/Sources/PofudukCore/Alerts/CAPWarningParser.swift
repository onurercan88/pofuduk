import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses CAP 1.2 (Common Alerting Protocol, the WMO standard for warnings) into `OfficialWarning`s.
/// Accepts a single <alert> or a document containing several. Prefers Turkish <info> blocks.
/// Level: MeteoAlarm-style `awareness_level` parameter ("2; yellow; Moderate") when present,
/// otherwise CAP severity (Moderate → yellow, Severe → orange, Extreme → red, Minor → green).
public enum CAPWarningParser {
    public static func parse(_ data: Data) -> [OfficialWarning]? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.alerts.compactMap(\.warning)
    }

    struct Info {
        var language = ""
        var event = "", headline = "", description = "", severity = "", web = ""
        var onset = "", effective = "", expires = ""
        var awareness = ""
        var areas: [String] = []
    }

    struct Alert {
        var identifier = ""
        var sent = ""
        var infos: [Info] = []

        var warning: OfficialWarning? {
            let info = infos.first { $0.language.lowercased().hasPrefix("tr") } ?? infos.first
            guard let info, let expires = CAPWarningParser.date(info.expires) else { return nil }
            let from = CAPWarningParser.date(info.onset) ?? CAPWarningParser.date(info.effective) ?? CAPWarningParser.date(sent)
            guard let from, let level = CAPWarningParser.level(awareness: info.awareness, severity: info.severity) else { return nil }
            let provinces = info.areas.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            return OfficialWarning(
                id: identifier.isEmpty ? UUID().uuidString : identifier, level: level,
                hazard: info.event.isEmpty ? info.headline : info.event,
                description: info.description.isEmpty ? info.headline : info.description,
                provinces: provinces, validFrom: from, validUntil: expires,
                sourceURL: URL(string: info.web) ?? MGMOfficialPage.warnings)
        }
    }

    static func level(awareness: String, severity: String) -> WarningLevel? {
        let a = awareness.lowercased()
        if a.contains("red") { return .red }
        if a.contains("orange") { return .orange }
        if a.contains("yellow") { return .yellow }
        if a.contains("green") { return .green }
        switch severity.lowercased() {
        case "extreme": return .red
        case "severe": return .orange
        case "moderate": return .yellow
        case "minor": return .green
        default: return nil
        }
    }

    static func date(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var alerts: [Alert] = []
        private var alert: Alert?
        private var info: Info?
        private var text = ""
        private var parameterName = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            switch local(name) {
            case "alert": alert = Alert()
            case "info": info = Info()
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local(name) {
            case "identifier": alert?.identifier = value
            case "sent": alert?.sent = value
            case "language": info?.language = value
            case "event": info?.event = value
            case "headline": info?.headline = value
            case "description": info?.description = value
            case "severity": info?.severity = value
            case "web": info?.web = value
            case "onset": info?.onset = value
            case "effective": info?.effective = value
            case "expires": info?.expires = value
            case "valueName": parameterName = value
            case "value": if parameterName.lowercased() == "awareness_level" { info?.awareness = value }
            case "areaDesc": info?.areas.append(value)
            case "info": if let i = info { alert?.infos.append(i) }; info = nil
            case "alert": if let a = alert { alerts.append(a) }; alert = nil
            default: break
            }
            text = ""
        }

        private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
    }
}
