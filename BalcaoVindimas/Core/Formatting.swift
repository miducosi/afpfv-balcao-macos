import Foundation

/// Dinheiro (cêntimos) e datas em pt-PT, como na web.
nonisolated enum Formatting {
    static let locale = Locale(identifier: "pt_PT")

    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter
    }()

    static func euros(_ cents: Int) -> String {
        currency.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100) €"
    }

    private static let instantWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let instant = Date.ISO8601FormatStyle()

    static func parseInstant(_ text: String) -> Date? {
        (try? instantWithFraction.parse(text)) ?? (try? instant.parse(text))
    }

    /// `AAAA-MM-DD` ↔ Date (meia-noite em Lisboa).
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Lisbon")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayString(_ date: Date) -> String { day.string(from: date) }
    static func parseDay(_ text: String) -> Date? { day.date(from: text) }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(locale))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// Data sem hora vinda da API (`AAAA-MM-DD`).
    static func day(_ text: String?) -> String {
        guard let text, let parsed = parseDay(text) else { return text ?? "—" }
        return parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }

    /// "1 pessoa" / "3 pessoas" — nunca "pessoa(s)".
    static func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
        "\(count) \(count == 1 ? singular : pluralForm)"
    }

    static func meters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + " m"
    }
}
