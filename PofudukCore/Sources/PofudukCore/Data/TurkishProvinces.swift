import Foundation

/// Offline list of Turkey's 81 provinces (plate code, name, approximate city-centre coordinate).
/// Used for manual selection without network. Districts are found via geocoding search.
public enum TurkishProvinces {
    public struct Province: Equatable, Sendable, Identifiable {
        public var id: Int { plate }
        public let plate: Int
        public let name: String
        public let coordinate: Coordinate

        public var place: Place {
            Place(name: name, province: name, coordinate: coordinate,
                  timeZoneIdentifier: "Europe/Istanbul", source: .manual)
        }
    }

    public static let all: [Province] = raw.map {
        Province(plate: $0.0, name: $0.1, coordinate: Coordinate(latitude: $0.2, longitude: $0.3))
    }

    /// Turkish-aware, diacritic-insensitive search ("istanbul" matches "İstanbul", "sanliurfa" matches "Şanlıurfa").
    public static func search(_ query: String) -> [Province] {
        let q = normalize(query)
        guard !q.isEmpty else { return all }
        return all.filter { normalize($0.name).contains(q) || String($0.plate) == q }
    }

    public static func normalize(_ s: String) -> String {
        let map: [Character: Character] = ["ı": "i", "İ": "i", "I": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g",
                                           "ü": "u", "Ü": "u", "ö": "o", "Ö": "o", "ç": "c", "Ç": "c", "â": "a", "î": "i", "û": "u"]
        return String(s.trimmingCharacters(in: .whitespaces).map { map[$0] ?? $0 }).lowercased()
    }

    private static let raw: [(Int, String, Double, Double)] = [
        (1, "Adana", 37.00, 35.32), (2, "Adıyaman", 37.76, 38.28), (3, "Afyonkarahisar", 38.76, 30.54),
        (4, "Ağrı", 39.72, 43.05), (5, "Amasya", 40.65, 35.83), (6, "Ankara", 39.93, 32.86),
        (7, "Antalya", 36.90, 30.70), (8, "Artvin", 41.18, 41.82), (9, "Aydın", 37.85, 27.85),
        (10, "Balıkesir", 39.65, 27.88), (11, "Bilecik", 40.14, 29.98), (12, "Bingöl", 38.88, 40.50),
        (13, "Bitlis", 38.40, 42.11), (14, "Bolu", 40.74, 31.61), (15, "Burdur", 37.72, 30.29),
        (16, "Bursa", 40.19, 29.06), (17, "Çanakkale", 40.15, 26.41), (18, "Çankırı", 40.60, 33.62),
        (19, "Çorum", 40.55, 34.95), (20, "Denizli", 37.78, 29.09), (21, "Diyarbakır", 37.91, 40.24),
        (22, "Edirne", 41.68, 26.56), (23, "Elazığ", 38.67, 39.22), (24, "Erzincan", 39.75, 39.49),
        (25, "Erzurum", 39.90, 41.27), (26, "Eskişehir", 39.78, 30.52), (27, "Gaziantep", 37.07, 37.38),
        (28, "Giresun", 40.91, 38.39), (29, "Gümüşhane", 40.46, 39.48), (30, "Hakkari", 37.58, 43.74),
        (31, "Hatay", 36.20, 36.16), (32, "Isparta", 37.76, 30.55), (33, "Mersin", 36.81, 34.64),
        (34, "İstanbul", 41.01, 28.98), (35, "İzmir", 38.42, 27.14), (36, "Kars", 40.60, 43.10),
        (37, "Kastamonu", 41.38, 33.78), (38, "Kayseri", 38.73, 35.48), (39, "Kırklareli", 41.73, 27.22),
        (40, "Kırşehir", 39.15, 34.16), (41, "Kocaeli", 40.77, 29.92), (42, "Konya", 37.87, 32.48),
        (43, "Kütahya", 39.42, 29.98), (44, "Malatya", 38.35, 38.31), (45, "Manisa", 38.61, 27.43),
        (46, "Kahramanmaraş", 37.58, 36.94), (47, "Mardin", 37.31, 40.74), (48, "Muğla", 37.22, 28.36),
        (49, "Muş", 38.75, 41.50), (50, "Nevşehir", 38.62, 34.71), (51, "Niğde", 37.97, 34.68),
        (52, "Ordu", 40.98, 37.88), (53, "Rize", 41.02, 40.52), (54, "Sakarya", 40.78, 30.40),
        (55, "Samsun", 41.29, 36.33), (56, "Siirt", 37.93, 41.94), (57, "Sinop", 42.03, 35.15),
        (58, "Sivas", 39.75, 37.02), (59, "Tekirdağ", 40.98, 27.51), (60, "Tokat", 40.31, 36.55),
        (61, "Trabzon", 41.00, 39.72), (62, "Tunceli", 39.11, 39.55), (63, "Şanlıurfa", 37.16, 38.79),
        (64, "Uşak", 38.68, 29.41), (65, "Van", 38.50, 43.38), (66, "Yozgat", 39.82, 34.81),
        (67, "Zonguldak", 41.45, 31.79), (68, "Aksaray", 38.37, 34.03), (69, "Bayburt", 40.26, 40.23),
        (70, "Karaman", 37.18, 33.22), (71, "Kırıkkale", 39.85, 33.51), (72, "Batman", 37.88, 41.13),
        (73, "Şırnak", 37.52, 42.46), (74, "Bartın", 41.64, 32.34), (75, "Ardahan", 41.11, 42.70),
        (76, "Iğdır", 39.92, 44.04), (77, "Yalova", 40.65, 29.27), (78, "Karabük", 41.20, 32.62),
        (79, "Kilis", 36.72, 37.12), (80, "Osmaniye", 37.07, 36.25), (81, "Düzce", 40.84, 31.16)
    ]
}
