import Foundation

/// One searchable city or time-zone entry for offline World Clock search.
struct CityEntry: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(name)|\(country)|\(timeZoneID)" }
    let name: String
    let country: String
    let timeZoneID: String
    /// Optional search aliases (e.g. "NYC", "PST", "SF", "Bengaluru").
    let aliases: [String]
    /// Higher priority ranks first on ties (major hubs > IANA cities > abbreviations).
    let priority: Int

    var displaySubtitle: String {
        country.isEmpty ? timeZoneID : "\(country) · \(timeZoneID)"
    }
}

/// Offline world-city and time-zone index: combines curated major cities, all IANA time zones
/// (enriched with country names from macOS's zone1970.tab), and common time-zone abbreviations.
enum CityIndex {
    nonisolated static let entries: [CityEntry] = buildEntries()

    /// Offline search matching city name, country, IANA identifier, or abbreviation.
    nonisolated static func search(_ rawQuery: String, limit: Int = 10, in catalog: [CityEntry] = entries) -> [CityEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        let underscoreQuery = query.replacingOccurrences(of: " ", with: "_")

        var scored: [(score: Int, priority: Int, entry: CityEntry)] = []
        scored.reserveCapacity(32)

        for entry in catalog {
            let nameLower = entry.name.lowercased()
            let countryLower = entry.country.lowercased()
            let tzLower = entry.timeZoneID.lowercased()
            let aliasMatch = entry.aliases.contains { $0.lowercased() == query }
            let aliasPrefix = !aliasMatch && entry.aliases.contains { $0.lowercased().hasPrefix(query) }

            let score: Int
            if nameLower == query || aliasMatch {
                score = 500
            } else if nameLower.hasPrefix(query) {
                score = 400
            } else if aliasPrefix || words(nameLower).contains(where: { $0.hasPrefix(query) }) {
                score = 320
            } else if nameLower.contains(query) {
                score = 240
            } else if countryLower == query {
                score = 210
            } else if countryLower.hasPrefix(query) {
                score = 180
            } else if tzLower.contains(underscoreQuery) || tzLower.contains(query) {
                score = 140
            } else if countryLower.contains(query) {
                score = 110
            } else {
                continue
            }
            scored.append((score, entry.priority, entry))
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.entry.name.localizedStandardCompare(b.entry.name) == .orderedAscending
        }

        // Deduplicate by (name, timeZoneID) while preserving best-ranked order.
        var seen = Set<String>()
        var result: [CityEntry] = []
        result.reserveCapacity(min(limit, scored.count))
        for item in scored {
            let key = "\(item.entry.name.lowercased())|\(item.entry.timeZoneID)"
            if seen.insert(key).inserted {
                result.append(item.entry)
                if result.count >= limit { break }
            }
        }
        return result
    }

    private nonisolated static func words(_ text: String) -> [Substring] {
        text.split { !$0.isLetter && !$0.isNumber }
    }

    /// Parses macOS's public-domain IANA `zone1970.tab` for timezone → localized country name.
    private nonisolated static func loadZoneCountries() -> [String: String] {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone1970.tab", encoding: .utf8) else { return [:] }
        let locale = Locale(identifier: "en_US")
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let cols = line.split(separator: "\t")
            guard cols.count >= 3 else { continue }
            let primaryCode = String(cols[0].split(separator: ",").first ?? "")
            let tz = String(cols[2])
            if let country = locale.localizedString(forRegionCode: primaryCode), !country.isEmpty {
                map[tz] = country
            }
        }
        return map
    }

    private nonisolated static func buildEntries() -> [CityEntry] {
        let countries = loadZoneCountries()
        var list: [CityEntry] = []
        list.reserveCapacity(800)

        // 1. Curated major world cities (many are not IANA zone names, e.g. San Francisco, Munich, Bangalore, Austin).
        for row in majorCities {
            guard row.2 == "UTC" || TimeZone(identifier: row.2) != nil else { continue }
            list.append(CityEntry(name: row.0, country: row.1, timeZoneID: row.2, aliases: row.3, priority: 100))
        }

        // 2. Every known IANA timezone city, enriched with its country name.
        var existingKeys = Set(list.map { "\($0.name.lowercased())|\($0.timeZoneID)" })
        for tz in TimeZone.knownTimeZoneIdentifiers {
            let city = WorldClock.cityName(tz)
            let key = "\(city.lowercased())|\(tz)"
            guard existingKeys.insert(key).inserted else { continue }
            let country = countries[tz] ?? ""
            list.append(CityEntry(name: city, country: country, timeZoneID: tz, aliases: [], priority: 50))
        }

        // 3. Common timezone abbreviations.
        for abbr in abbreviations {
            guard abbr.2 == "UTC" || TimeZone(identifier: abbr.2) != nil else { continue }
            list.append(CityEntry(name: abbr.0, country: abbr.1, timeZoneID: abbr.2, aliases: abbr.3, priority: 80))
        }

        return list
    }

    // (City, Country, IANA TimeZone, Aliases)
    private nonisolated static let majorCities: [(String, String, String, [String])] = [
        // North America
        ("New York", "United States", "America/New_York", ["NYC", "Manhattan", "EST", "EDT"]),
        ("San Francisco", "United States", "America/Los_Angeles", ["SF", "Bay Area", "Silicon Valley", "PST", "PDT"]),
        ("Los Angeles", "United States", "America/Los_Angeles", ["LA", "PST", "PDT"]),
        ("Seattle", "United States", "America/Los_Angeles", ["SEA"]),
        ("San Jose", "United States", "America/Los_Angeles", ["SJC"]),
        ("San Diego", "United States", "America/Los_Angeles", []),
        ("Portland", "United States", "America/Los_Angeles", ["PDX"]),
        ("Las Vegas", "United States", "America/Los_Angeles", []),
        ("Chicago", "United States", "America/Chicago", ["CST", "CDT"]),
        ("Austin", "United States", "America/Chicago", ["ATX"]),
        ("Dallas", "United States", "America/Chicago", ["DFW"]),
        ("Houston", "United States", "America/Chicago", []),
        ("Minneapolis", "United States", "America/Chicago", []),
        ("Nashville", "United States", "America/Chicago", []),
        ("New Orleans", "United States", "America/Chicago", []),
        ("Boston", "United States", "America/New_York", ["BOS"]),
        ("Washington, D.C.", "United States", "America/New_York", ["DC", "Washington"]),
        ("Miami", "United States", "America/New_York", ["MIA"]),
        ("Atlanta", "United States", "America/New_York", ["ATL"]),
        ("Philadelphia", "United States", "America/New_York", ["Philly"]),
        ("Pittsburgh", "United States", "America/New_York", []),
        ("Orlando", "United States", "America/New_York", []),
        ("Raleigh", "United States", "America/New_York", []),
        ("Charlotte", "United States", "America/New_York", []),
        ("Detroit", "United States", "America/Detroit", []),
        ("Denver", "United States", "America/Denver", ["MST", "MDT"]),
        ("Salt Lake City", "United States", "America/Denver", ["SLC"]),
        ("Phoenix", "United States", "America/Phoenix", []),
        ("Honolulu", "United States", "Pacific/Honolulu", ["Hawaii", "HST"]),
        ("Anchorage", "United States", "America/Anchorage", ["Alaska"]),
        ("Toronto", "Canada", "America/Toronto", ["YYZ"]),
        ("Montreal", "Canada", "America/Toronto", ["Montréal", "YUL"]),
        ("Ottawa", "Canada", "America/Toronto", []),
        ("Vancouver", "Canada", "America/Vancouver", ["YVR"]),
        ("Calgary", "Canada", "America/Edmonton", []),
        ("Edmonton", "Canada", "America/Edmonton", []),
        ("Winnipeg", "Canada", "America/Winnipeg", []),
        ("Halifax", "Canada", "America/Halifax", []),
        ("Mexico City", "Mexico", "America/Mexico_City", ["CDMX"]),
        ("Guadalajara", "Mexico", "America/Mexico_City", []),
        ("Monterrey", "Mexico", "America/Monterrey", []),
        ("Cancún", "Mexico", "America/Cancun", ["Cancun"]),

        // South & Central America
        ("São Paulo", "Brazil", "America/Sao_Paulo", ["Sao Paulo"]),
        ("Rio de Janeiro", "Brazil", "America/Sao_Paulo", ["Rio"]),
        ("Brasília", "Brazil", "America/Sao_Paulo", ["Brasilia"]),
        ("Belo Horizonte", "Brazil", "America/Sao_Paulo", []),
        ("Buenos Aires", "Argentina", "America/Argentina/Buenos_Aires", []),
        ("Santiago", "Chile", "America/Santiago", []),
        ("Bogotá", "Colombia", "America/Bogota", ["Bogota"]),
        ("Medellín", "Colombia", "America/Bogota", ["Medellin"]),
        ("Lima", "Peru", "America/Lima", []),
        ("Quito", "Ecuador", "America/Guayaquil", []),
        ("Montevideo", "Uruguay", "America/Montevideo", []),
        ("Caracas", "Venezuela", "America/Caracas", []),
        ("Panama City", "Panama", "America/Panama", []),
        ("San José", "Costa Rica", "America/Costa_Rica", ["San Jose CR"]),

        // Europe
        ("London", "United Kingdom", "Europe/London", ["UK", "BST", "GMT"]),
        ("Edinburgh", "United Kingdom", "Europe/London", ["Scotland"]),
        ("Manchester", "United Kingdom", "Europe/London", []),
        ("Birmingham", "United Kingdom", "Europe/London", []),
        ("Bristol", "United Kingdom", "Europe/London", []),
        ("Glasgow", "United Kingdom", "Europe/London", []),
        ("Belfast", "United Kingdom", "Europe/London", []),
        ("Dublin", "Ireland", "Europe/Dublin", []),
        ("Paris", "France", "Europe/Paris", ["CET", "CEST"]),
        ("Lyon", "France", "Europe/Paris", []),
        ("Marseille", "France", "Europe/Paris", []),
        ("Toulouse", "France", "Europe/Paris", []),
        ("Nice", "France", "Europe/Paris", []),
        ("Berlin", "Germany", "Europe/Berlin", ["CET", "CEST"]),
        ("Munich", "Germany", "Europe/Berlin", ["München"]),
        ("Frankfurt", "Germany", "Europe/Berlin", []),
        ("Hamburg", "Germany", "Europe/Berlin", []),
        ("Cologne", "Germany", "Europe/Berlin", ["Köln"]),
        ("Stuttgart", "Germany", "Europe/Berlin", []),
        ("Düsseldorf", "Germany", "Europe/Berlin", ["Dusseldorf"]),
        ("Amsterdam", "Netherlands", "Europe/Amsterdam", ["AMS"]),
        ("Rotterdam", "Netherlands", "Europe/Amsterdam", []),
        ("The Hague", "Netherlands", "Europe/Amsterdam", []),
        ("Brussels", "Belgium", "Europe/Brussels", []),
        ("Antwerp", "Belgium", "Europe/Brussels", []),
        ("Zurich", "Switzerland", "Europe/Zurich", ["Zürich"]),
        ("Geneva", "Switzerland", "Europe/Zurich", ["Genève"]),
        ("Basel", "Switzerland", "Europe/Zurich", []),
        ("Bern", "Switzerland", "Europe/Zurich", []),
        ("Vienna", "Austria", "Europe/Vienna", ["Wien"]),
        ("Madrid", "Spain", "Europe/Madrid", []),
        ("Barcelona", "Spain", "Europe/Madrid", ["BCN"]),
        ("Valencia", "Spain", "Europe/Madrid", []),
        ("Seville", "Spain", "Europe/Madrid", ["Sevilla"]),
        ("Malaga", "Spain", "Europe/Madrid", ["Málaga"]),
        ("Lisbon", "Portugal", "Europe/Lisbon", ["Lisboa"]),
        ("Porto", "Portugal", "Europe/Lisbon", []),
        ("Rome", "Italy", "Europe/Rome", ["Roma"]),
        ("Milan", "Italy", "Europe/Rome", ["Milano"]),
        ("Florence", "Italy", "Europe/Rome", ["Firenze"]),
        ("Naples", "Italy", "Europe/Rome", ["Napoli"]),
        ("Turin", "Italy", "Europe/Rome", ["Torino"]),
        ("Venice", "Italy", "Europe/Rome", ["Venezia"]),
        ("Stockholm", "Sweden", "Europe/Stockholm", []),
        ("Gothenburg", "Sweden", "Europe/Stockholm", ["Göteborg"]),
        ("Malmö", "Sweden", "Europe/Stockholm", ["Malmo"]),
        ("Copenhagen", "Denmark", "Europe/Copenhagen", ["København"]),
        ("Oslo", "Norway", "Europe/Oslo", []),
        ("Bergen", "Norway", "Europe/Oslo", []),
        ("Helsinki", "Finland", "Europe/Helsinki", []),
        ("Reykjavik", "Iceland", "Atlantic/Reykjavik", ["Reykjavík"]),
        ("Warsaw", "Poland", "Europe/Warsaw", ["Warszawa"]),
        ("Kraków", "Poland", "Europe/Warsaw", ["Krakow"]),
        ("Wrocław", "Poland", "Europe/Warsaw", ["Wroclaw"]),
        ("Gdańsk", "Poland", "Europe/Warsaw", ["Gdansk"]),
        ("Prague", "Czechia", "Europe/Prague", ["Praha"]),
        ("Budapest", "Hungary", "Europe/Budapest", []),
        ("Bucharest", "Romania", "Europe/Bucharest", []),
        ("Sofia", "Bulgaria", "Europe/Sofia", []),
        ("Athens", "Greece", "Europe/Athens", []),
        ("Thessaloniki", "Greece", "Europe/Athens", []),
        ("Istanbul", "Türkiye", "Europe/Istanbul", ["Turkey"]),
        ("Ankara", "Türkiye", "Europe/Istanbul", []),
        ("Izmir", "Türkiye", "Europe/Istanbul", []),
        ("Kyiv", "Ukraine", "Europe/Kyiv", ["Kiev"]),
        ("Lviv", "Ukraine", "Europe/Kyiv", []),
        ("Moscow", "Russia", "Europe/Moscow", []),
        ("Saint Petersburg", "Russia", "Europe/Moscow", ["St Petersburg"]),
        ("Belgrade", "Serbia", "Europe/Belgrade", []),
        ("Zagreb", "Croatia", "Europe/Zagreb", []),
        ("Ljubljana", "Slovenia", "Europe/Ljubljana", []),
        ("Tallinn", "Estonia", "Europe/Tallinn", []),
        ("Riga", "Latvia", "Europe/Riga", []),
        ("Vilnius", "Lithuania", "Europe/Vilnius", []),
        ("Luxembourg", "Luxembourg", "Europe/Luxembourg", []),

        // South Asia
        ("Kathmandu", "Nepal", "Asia/Kathmandu", ["NPT", "KTM", "Nepal"]),
        ("Pokhara", "Nepal", "Asia/Kathmandu", []),
        ("Lalitpur", "Nepal", "Asia/Kathmandu", ["Patan"]),
        ("Bengaluru", "India", "Asia/Kolkata", ["Bangalore", "BLR", "IST"]),
        ("Mumbai", "India", "Asia/Kolkata", ["Bombay", "BOM", "IST"]),
        ("New Delhi", "India", "Asia/Kolkata", ["Delhi", "DEL", "IST"]),
        ("Hyderabad", "India", "Asia/Kolkata", ["HYD"]),
        ("Chennai", "India", "Asia/Kolkata", ["Madras"]),
        ("Kolkata", "India", "Asia/Kolkata", ["Calcutta"]),
        ("Pune", "India", "Asia/Kolkata", []),
        ("Ahmedabad", "India", "Asia/Kolkata", []),
        ("Jaipur", "India", "Asia/Kolkata", []),
        ("Kochi", "India", "Asia/Kolkata", []),
        ("Gurugram", "India", "Asia/Kolkata", ["Gurgaon"]),
        ("Noida", "India", "Asia/Kolkata", []),
        ("Karachi", "Pakistan", "Asia/Karachi", ["PKT"]),
        ("Lahore", "Pakistan", "Asia/Karachi", []),
        ("Islamabad", "Pakistan", "Asia/Karachi", []),
        ("Dhaka", "Bangladesh", "Asia/Dhaka", ["BST"]),
        ("Colombo", "Sri Lanka", "Asia/Colombo", []),
        ("Thimphu", "Bhutan", "Asia/Thimphu", []),

        // East & Southeast Asia
        ("Tokyo", "Japan", "Asia/Tokyo", ["JST", "TYO"]),
        ("Osaka", "Japan", "Asia/Tokyo", []),
        ("Kyoto", "Japan", "Asia/Tokyo", []),
        ("Yokohama", "Japan", "Asia/Tokyo", []),
        ("Nagoya", "Japan", "Asia/Tokyo", []),
        ("Sapporo", "Japan", "Asia/Tokyo", []),
        ("Fukuoka", "Japan", "Asia/Tokyo", []),
        ("Seoul", "South Korea", "Asia/Seoul", ["KST", "ICN"]),
        ("Busan", "South Korea", "Asia/Seoul", []),
        ("Incheon", "South Korea", "Asia/Seoul", []),
        ("Shanghai", "China", "Asia/Shanghai", ["CST"]),
        ("Beijing", "China", "Asia/Shanghai", ["Peking"]),
        ("Shenzhen", "China", "Asia/Shanghai", []),
        ("Guangzhou", "China", "Asia/Shanghai", ["Canton"]),
        ("Chengdu", "China", "Asia/Shanghai", []),
        ("Hangzhou", "China", "Asia/Shanghai", []),
        ("Nanjing", "China", "Asia/Shanghai", []),
        ("Wuhan", "China", "Asia/Shanghai", []),
        ("Xi'an", "China", "Asia/Shanghai", ["Xian"]),
        ("Hong Kong", "Hong Kong", "Asia/Hong_Kong", ["HK", "HKT"]),
        ("Taipei", "Taiwan", "Asia/Taipei", []),
        ("Singapore", "Singapore", "Asia/Singapore", ["SG", "SGT"]),
        ("Kuala Lumpur", "Malaysia", "Asia/Kuala_Lumpur", ["KL", "MYT"]),
        ("Penang", "Malaysia", "Asia/Kuala_Lumpur", []),
        ("Bangkok", "Thailand", "Asia/Bangkok", ["BKK", "ICT"]),
        ("Chiang Mai", "Thailand", "Asia/Bangkok", []),
        ("Phuket", "Thailand", "Asia/Bangkok", []),
        ("Ho Chi Minh City", "Vietnam", "Asia/Ho_Chi_Minh", ["Saigon", "HCMC"]),
        ("Hanoi", "Vietnam", "Asia/Bangkok", []),
        ("Da Nang", "Vietnam", "Asia/Ho_Chi_Minh", []),
        ("Jakarta", "Indonesia", "Asia/Jakarta", ["WIB"]),
        ("Surabaya", "Indonesia", "Asia/Jakarta", []),
        ("Bandung", "Indonesia", "Asia/Jakarta", []),
        ("Bali", "Indonesia", "Asia/Makassar", ["Denpasar", "WITA"]),
        ("Manila", "Philippines", "Asia/Manila", ["PHT"]),
        ("Cebu", "Philippines", "Asia/Manila", []),
        ("Phnom Penh", "Cambodia", "Asia/Phnom_Penh", []),
        ("Yangon", "Myanmar", "Asia/Yangon", []),

        // Middle East & Central Asia
        ("Dubai", "United Arab Emirates", "Asia/Dubai", ["UAE", "DXB", "GST"]),
        ("Abu Dhabi", "United Arab Emirates", "Asia/Dubai", []),
        ("Doha", "Qatar", "Asia/Qatar", []),
        ("Riyadh", "Saudi Arabia", "Asia/Riyadh", []),
        ("Jeddah", "Saudi Arabia", "Asia/Riyadh", []),
        ("Kuwait City", "Kuwait", "Asia/Kuwait", []),
        ("Muscat", "Oman", "Asia/Muscat", []),
        ("Manama", "Bahrain", "Asia/Bahrain", []),
        ("Tel Aviv", "Israel", "Asia/Jerusalem", ["TLV"]),
        ("Jerusalem", "Israel", "Asia/Jerusalem", []),
        ("Amman", "Jordan", "Asia/Amman", []),
        ("Beirut", "Lebanon", "Asia/Beirut", []),
        ("Tehran", "Iran", "Asia/Tehran", []),
        ("Almaty", "Kazakhstan", "Asia/Almaty", []),
        ("Tashkent", "Uzbekistan", "Asia/Tashkent", []),
        ("Tbilisi", "Georgia", "Asia/Tbilisi", []),
        ("Baku", "Azerbaijan", "Asia/Baku", []),
        ("Yerevan", "Armenia", "Asia/Yerevan", []),

        // Oceania
        ("Sydney", "Australia", "Australia/Sydney", ["SYD", "AEST", "AEDT"]),
        ("Melbourne", "Australia", "Australia/Melbourne", ["MEL"]),
        ("Brisbane", "Australia", "Australia/Brisbane", ["BNE"]),
        ("Perth", "Australia", "Australia/Perth", ["AWST"]),
        ("Adelaide", "Australia", "Australia/Adelaide", ["ACST"]),
        ("Canberra", "Australia", "Australia/Sydney", []),
        ("Hobart", "Australia", "Australia/Hobart", []),
        ("Auckland", "New Zealand", "Pacific/Auckland", ["AKL", "NZST", "NZDT"]),
        ("Wellington", "New Zealand", "Pacific/Auckland", []),
        ("Christchurch", "New Zealand", "Pacific/Auckland", []),
        ("Suva", "Fiji", "Pacific/Fiji", []),

        // Africa
        ("Cairo", "Egypt", "Africa/Cairo", ["EET"]),
        ("Alexandria", "Egypt", "Africa/Cairo", []),
        ("Johannesburg", "South Africa", "Africa/Johannesburg", ["Joburg", "SAST"]),
        ("Cape Town", "South Africa", "Africa/Johannesburg", []),
        ("Durban", "South Africa", "Africa/Johannesburg", []),
        ("Lagos", "Nigeria", "Africa/Lagos", ["WAT"]),
        ("Abuja", "Nigeria", "Africa/Lagos", []),
        ("Nairobi", "Kenya", "Africa/Nairobi", ["EAT"]),
        ("Addis Ababa", "Ethiopia", "Africa/Addis_Ababa", []),
        ("Accra", "Ghana", "Africa/Accra", []),
        ("Casablanca", "Morocco", "Africa/Casablanca", []),
        ("Marrakesh", "Morocco", "Africa/Casablanca", ["Marrakech"]),
        ("Algiers", "Algeria", "Africa/Algiers", []),
        ("Tunis", "Tunisia", "Africa/Tunis", []),
        ("Kigali", "Rwanda", "Africa/Kigali", []),
        ("Kampala", "Uganda", "Africa/Kampala", []),
        ("Dar es Salaam", "Tanzania", "Africa/Dar_es_Salaam", []),
    ]

    private nonisolated static let abbreviations: [(String, String, String, [String])] = [
        ("UTC", "Coordinated Universal Time", "UTC", ["GMT", "Zulu", "Z"]),
        ("GMT", "Greenwich Mean Time", "GMT", ["UTC"]),
        ("Eastern Time (US)", "United States", "America/New_York", ["EST", "EDT", "ET"]),
        ("Central Time (US)", "United States", "America/Chicago", ["CST", "CDT", "CT"]),
        ("Mountain Time (US)", "United States", "America/Denver", ["MST", "MDT", "MT"]),
        ("Pacific Time (US)", "United States", "America/Los_Angeles", ["PST", "PDT", "PT"]),
        ("Central European Time", "Europe", "Europe/Berlin", ["CET", "CEST"]),
        ("India Standard Time", "India", "Asia/Kolkata", ["IST"]),
        ("Nepal Time", "Nepal", "Asia/Kathmandu", ["NPT"]),
        ("Japan Standard Time", "Japan", "Asia/Tokyo", ["JST"]),
        ("Korea Standard Time", "South Korea", "Asia/Seoul", ["KST"]),
        ("Singapore Time", "Singapore", "Asia/Singapore", ["SGT"]),
        ("Australian Eastern Time", "Australia", "Australia/Sydney", ["AEST", "AEDT"]),
    ]
}
