import Foundation

/// A calendar day (no time, no time zone), as written in the dataset
/// (`YYYY-MM-DD`).
public struct DayDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Parses `YYYY-MM-DD`; nil for any other form or an impossible day.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m) else { return nil }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        guard (1...days).contains(d) else { return nil }
        year = y; month = m; day = d
    }

    public var description: String {
        let pad = { (n: Int, w: Int) -> String in String(repeating: "0", count: max(0, w - String(n).count)) + String(n) }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (a: DayDate, b: DayDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// One row of `country_summary.csv`. Optional numbers and dates are nil when
/// the dataset leaves them empty.
public struct CountrySummary: Hashable, Sendable {
    /// ISO 3166-1 alpha-2.
    public let iso: String
    /// Country name.
    public let name: String
    /// Region, see ``EmployerCosts/regions()``.
    public let region: String
    /// ISO 4217 local currency.
    public let currency: String
    /// Illustrative gross annual salary in USD (an example, not a median).
    public let exampleSalaryUSD: Int
    /// Illustrative role.
    public let exampleRole: String
    /// State, province or city the lines are priced for, when not national.
    public let examplePlace: String
    /// Share of gross taken as basic pay by lines with base `basic`.
    public let basicShareOfGross: Double?
    /// Statutory employer cost, percent of gross at the example salary.
    public let employerCostPct: Double
    /// The same percent as printed on eorscope.com (1 decimal).
    public let employerCostPctPrinted: Double
    /// The employer cost is an "at least" figure, not a total.
    public let totalDeclaredFloor: Bool
    /// The modelled contribution base is the highest the law allows; lines
    /// with ``Contribution/inTotal`` false come on top.
    public let totalDeclaredCeiling: Bool
    /// Statutory employer cost per month in USD at the example salary.
    public let employerCostUSDMonth: Double
    /// A cost the total leaves out.
    public let totalExcludes: String
    /// Local currency units per 1 USD used for the conversion.
    public let fxLocalPerUSD: Double
    /// Date of the exchange rate (nil for USD).
    public let fxDate: DayDate?
    /// Date the country data was last verified.
    public let lastReviewed: DayDate?
}

/// One row of `country_contributions.csv`: an employer contribution
/// (`lineType` "contribution") or a statutory extra (`lineType`
/// "statutory_extra").
public struct Contribution: Hashable, Sendable {
    public let iso: String
    public let country: String
    public let currency: String
    /// `contribution` or `statutory_extra`.
    public let lineType: String
    /// Unique within the country and line type.
    public let lineID: String
    public let lineName: String
    /// Decimal (0.12 = 12 %); nil for statutory extras.
    public let rate: Double?
    /// `gross`, `basic`, `flat`, `band`, or empty (statutory extras).
    public let base: String
    /// Multiplier on the base, applied before floor and cap (1 = the salary
    /// itself); nil for flat lines and statutory extras.
    public let baseFactor: Double?
    /// Yearly floor on the base, local currency.
    public let baseFloorAnnualLocal: Double?
    /// Yearly ceiling on the base, local currency.
    public let baseCapAnnualLocal: Double?
    /// Fixed yearly amount when base is `flat`.
    public let flatAnnualLocal: Double?
    /// The line applies only when annual gross is at least this.
    public let minGrossAnnualLocal: Double?
    /// The line applies only when annual gross is at most this.
    public let maxGrossAnnualLocal: Double?
    /// `percent`, `months`, `days`, or empty (contributions).
    public let extraKind: String
    /// Value in the unit given by ``extraKind``.
    public let extraValue: Double?
    /// The line rests, in whole or in part, on a non-official source.
    public let secondarySource: Bool
    /// The country mandates a 13th-month salary.
    public let thirteenthMonth: Bool
    /// The country's employer cost is an "at least" figure.
    public let totalDeclaredFloor: Bool
    /// The modelled base is the highest the law allows.
    public let totalDeclaredCeiling: Bool
    /// The line is included in the employer cost total.
    public let inTotal: Bool
    /// Condition in plain words.
    public let applies: String
    public let notes: String
    public let sourceName: String
    public let sourceURL: String
    public let sourceCheckedAt: DayDate?
}

/// One row of `country_assumptions.csv`: the case a country's lines and total
/// are priced for.
public struct Assumption: Hashable, Sendable {
    public let iso: String
    /// Unique within the country.
    public let id: String
    public let label: String
    /// A share, a rate, a threshold, or 1 for a stated condition.
    public let value: Double
    public let notes: String
}

/// Read-only lookup of the EOR Scope dataset of statutory employer costs,
/// embedded as package resources. No dependencies, no network calls.
///
/// The package returns the figures as exported and computes nothing: employer
/// cost totals are the ones published in the dataset. For a cost at another
/// salary, use the calculator at https://eorscope.com/eor-cost-calculator/.
///
/// A country flagged ``CountrySummary/totalDeclaredFloor`` publishes an
/// "at least" figure, not a total. Under
/// ``CountrySummary/totalDeclaredCeiling`` the modelled contribution base is
/// the highest the law allows, and lines with ``Contribution/inTotal`` false
/// come on top. A contribution's ``Contribution/rate`` applies to its
/// ``Contribution/base`` times ``Contribution/baseFactor`` (1 unless the law
/// builds the base from more than the salary, as Mexico's integrated base
/// does), before ``Contribution/baseFloorAnnualLocal`` and
/// ``Contribution/baseCapAnnualLocal``.
///
/// Sources and method: https://eorscope.com/methodology/. Cost comparison,
/// not legal or tax advice.
public enum EmployerCosts {
    /// Every country, sorted by ISO code.
    public static func countries() -> [CountrySummary] { store.countries }

    /// The country with the given ISO 3166-1 alpha-2 code (case-insensitive).
    public static func country(_ iso: String) -> CountrySummary? {
        let iso = iso.uppercased()
        return store.countries.first { $0.iso == iso }
    }

    /// The distinct regions, sorted.
    public static func regions() -> [String] {
        Array(Set(store.countries.map(\.region))).sorted()
    }

    /// The countries of a region (case-insensitive), sorted by ISO code.
    public static func countries(inRegion region: String) -> [CountrySummary] {
        let r = region.lowercased()
        return store.countries.filter { $0.region.lowercased() == r }
    }

    /// The contribution and statutory extra lines of a country, in dataset
    /// order; empty for an unknown code.
    public static func contributions(_ iso: String) -> [Contribution] {
        store.contributions[iso.uppercased()] ?? []
    }

    /// The declared assumptions of a country, in dataset order.
    public static func assumptions(_ iso: String) -> [Assumption] {
        store.assumptions[iso.uppercased()] ?? []
    }

    static let store: Store = {
        do { return try Store.load() } catch { fatalError("EORScopeEmployerCosts: embedded dataset: \(error)") }
    }()
}

// MARK: - loading

struct Store {
    var countries: [CountrySummary] = []
    var contributions: [String: [Contribution]] = [:]
    var assumptions: [String: [Assumption]] = [:]

    static func resource(_ name: String) throws -> [UInt8] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "data") else {
            throw CSVError(description: "\(name).csv: missing resource")
        }
        return [UInt8](try Data(contentsOf: url))
    }

    static func rows(_ name: String, _ body: (inout Row) -> Void) throws {
        let recs = try parseCSV(try resource(name), name: name + ".csv")
        var idx: [String: Int] = [:]
        for (i, h) in recs[0].enumerated() { idx[h] = i }
        for (n, rec) in recs.dropFirst().enumerated() {
            var r = Row(idx: idx, rec: rec, file: name + ".csv", line: n + 2)
            body(&r)
            if let e = r.error { throw e }
        }
    }

    static func load() throws -> Store {
        var s = Store()
        try rows("country_summary") { r in
            let salary = r.optInt("example_salary_usd")
            if salary == nil { r.fail("example_salary_usd: empty") }
            s.countries.append(CountrySummary(
                iso: r.str("iso"), name: r.str("country"), region: r.str("region"), currency: r.str("currency"),
                exampleSalaryUSD: salary ?? 0, exampleRole: r.str("example_role"),
                examplePlace: r.str("example_place"), basicShareOfGross: r.optDouble("basic_share_of_gross"),
                employerCostPct: r.double("employer_cost_pct"),
                employerCostPctPrinted: r.double("employer_cost_pct_printed"),
                totalDeclaredFloor: r.bool("total_declared_floor"),
                totalDeclaredCeiling: r.bool("total_declared_ceiling"),
                employerCostUSDMonth: r.double("employer_cost_usd_month"),
                totalExcludes: r.str("total_excludes"), fxLocalPerUSD: r.double("fx_local_per_usd"),
                fxDate: r.date("fx_date"), lastReviewed: r.date("last_reviewed")))
        }
        s.countries.sort { $0.iso < $1.iso }

        try rows("country_contributions") { r in
            let c = Contribution(
                iso: r.str("iso"), country: r.str("country"), currency: r.str("currency"),
                lineType: r.str("line_type"), lineID: r.str("line_id"), lineName: r.str("line_name"),
                rate: r.optDouble("rate"), base: r.str("base"), baseFactor: r.optDouble("base_factor"),
                baseFloorAnnualLocal: r.optDouble("base_floor_annual_local"),
                baseCapAnnualLocal: r.optDouble("base_cap_annual_local"),
                flatAnnualLocal: r.optDouble("flat_annual_local"),
                minGrossAnnualLocal: r.optDouble("min_gross_annual_local"),
                maxGrossAnnualLocal: r.optDouble("max_gross_annual_local"),
                extraKind: r.str("extra_kind"), extraValue: r.optDouble("extra_value"),
                secondarySource: r.bool("secondary_source"), thirteenthMonth: r.bool("thirteenth_month"),
                totalDeclaredFloor: r.bool("total_declared_floor"),
                totalDeclaredCeiling: r.bool("total_declared_ceiling"), inTotal: r.bool("in_total"),
                applies: r.str("applies"), notes: r.str("notes"), sourceName: r.str("source_name"),
                sourceURL: r.str("source_url"), sourceCheckedAt: r.date("source_checked_at"))
            s.contributions[c.iso, default: []].append(c)
        }

        try rows("country_assumptions") { r in
            let a = Assumption(iso: r.str("iso"), id: r.str("id"), label: r.str("label"),
                               value: r.double("value"), notes: r.str("notes"))
            s.assumptions[a.iso, default: []].append(a)
        }
        return s
    }
}

struct Row {
    let idx: [String: Int]
    let rec: [String]
    let file: String
    let line: Int
    var error: CSVError?

    mutating func fail(_ msg: String) {
        if error == nil { error = CSVError(description: "\(file): line \(line): \(msg)") }
    }

    mutating func str(_ col: String) -> String {
        guard let i = idx[col] else { fail("missing column \"\(col)\""); return "" }
        return rec[i]
    }

    mutating func optDouble(_ col: String) -> Double? {
        let s = str(col)
        if s.isEmpty { return nil }
        guard let d = Double(s) else { fail("\(col): invalid number \"\(s)\""); return nil }
        return d
    }

    mutating func double(_ col: String) -> Double {
        if let d = optDouble(col) { return d }
        fail("\(col): empty")
        return 0
    }

    mutating func optInt(_ col: String) -> Int? {
        let s = str(col)
        if s.isEmpty { return nil }
        guard let n = Int(s) else { fail("\(col): invalid integer \"\(s)\""); return nil }
        return n
    }

    /// Same spellings as Go's strconv.ParseBool.
    mutating func bool(_ col: String) -> Bool {
        let s = str(col)
        switch s {
        case "1", "t", "T", "true", "TRUE", "True": return true
        case "0", "f", "F", "false", "FALSE", "False": return false
        default: fail("\(col): invalid boolean \"\(s)\""); return false
        }
    }

    mutating func date(_ col: String) -> DayDate? {
        let s = str(col)
        if s.isEmpty { return nil }
        guard let d = DayDate(s) else { fail("\(col): invalid date \"\(s)\""); return nil }
        return d
    }
}
