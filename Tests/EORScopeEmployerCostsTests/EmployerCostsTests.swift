import Foundation
import XCTest
@testable import EORScopeEmployerCosts

/// Raw bytes of an embedded CSV, read without the package's parser.
private func raw(_ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "data"))
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

/// Records in a CSV text counted independently of parseCSV: line breaks
/// outside quotes, minus the header.
private func countRecords(_ text: String) -> Int {
    var n = 0, inQ = false
    for c in text.unicodeScalars {
        if c == "\"" { inQ.toggle() } else if c == "\n" && !inQ { n += 1 }
    }
    if let last = text.unicodeScalars.last, last != "\n" { n += 1 }
    return n - 1
}

private func isUpperCode(_ s: String, _ n: Int) -> Bool {
    s.count == n && s.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
}

final class EmployerCostsTests: XCTestCase {
    // The parser: quotes, commas, doubled quotes, line breaks, CRLF, BOM, blank lines.
    func testParser() throws {
        let text = "\u{FEFF}a,b,c\r\n\"x, y\",\"say \"\"hi\"\"\",\"l1\nl2\"\r\n\n,,\"\"\n1,2,3"
        let r = try parseCSV(Array(text.utf8), name: "t")
        XCTAssertEqual(r, [["a", "b", "c"], ["x, y", "say \"hi\"", "l1\nl2"], ["", "", ""], ["1", "2", "3"]])
        for bad in ["a,b\n1\n", "a\n\"x\"y\n", "a\nx\"y\n", "a\n\"open\n", ""] {
            XCTAssertThrowsError(try parseCSV(Array(bad.utf8), name: "t"), bad)
        }
    }

    // 76 countries, valid codes, case-insensitive lookup.
    func testCountries() throws {
        let cs = EmployerCosts.countries()
        XCTAssertEqual(cs.count, 76)
        XCTAssertEqual(cs.count, countRecords(try raw("country_summary")))
        XCTAssertEqual(cs.map(\.iso), cs.map(\.iso).sorted())
        var seen = Set<String>()
        for c in cs {
            XCTAssertTrue(isUpperCode(c.iso, 2) && seen.insert(c.iso).inserted, c.iso)
            XCTAssertTrue(!c.name.isEmpty && !c.region.isEmpty && isUpperCode(c.currency, 3), c.iso)
            XCTAssertTrue(c.exampleSalaryUSD > 0 && c.fxLocalPerUSD > 0 && c.employerCostPct >= 0
                          && c.employerCostUSDMonth >= 0, c.iso)
            XCTAssertNotNil(c.lastReviewed, c.iso)
            XCTAssertTrue(c.currency == "USD" || c.fxDate != nil, c.iso)
            if let s = c.basicShareOfGross { XCTAssertTrue(s > 0 && s <= 1, c.iso) }
            XCTAssertEqual(EmployerCosts.country(c.iso)?.iso, c.iso)
        }
        XCTAssertNil(EmployerCosts.country("xx"))
        XCTAssertEqual(EmployerCosts.country("de")?.iso, "DE")
    }

    // Published figures of the 2026-10-13 export, read from the CSV by an
    // independent script (MX printed 30.9 as on eorscope.com).
    func testKnownFigures() throws {
        let mx = try XCTUnwrap(EmployerCosts.country("MX"))
        XCTAssertEqual(mx.employerCostPctPrinted, 30.9)
        XCTAssertEqual(mx.exampleSalaryUSD, 36000)
        XCTAssertEqual(mx.employerCostPct, 30.9336)
        XCTAssertEqual(mx.employerCostUSDMonth, 928.01)
        XCTAssertEqual(mx.fxLocalPerUSD, 18.125583)
        XCTAssertEqual(mx.fxDate?.description, "2026-09-30")

        let de = try XCTUnwrap(EmployerCosts.country("DE"))
        XCTAssertEqual(de.exampleSalaryUSD, 75000)
        XCTAssertEqual(de.employerCostPct, 22.25)
        XCTAssertEqual(de.employerCostPctPrinted, 22.3)
        XCTAssertEqual(de.employerCostUSDMonth, 1390.63)
        XCTAssertEqual(de.fxLocalPerUSD, 0.880669)

        let fr = try XCTUnwrap(EmployerCosts.country("FR"))
        XCTAssertEqual(fr.exampleSalaryUSD, 80000)
        XCTAssertEqual(fr.employerCostPct, 48.2197)
        XCTAssertEqual(fr.employerCostPctPrinted, 48.2)
        XCTAssertEqual(fr.employerCostUSDMonth, 3214.65)

        let ae = try XCTUnwrap(EmployerCosts.country("AE"))
        XCTAssertEqual(ae.employerCostPct, 2.8767)
        XCTAssertEqual(ae.employerCostUSDMonth, 155.82)

        let us = try XCTUnwrap(EmployerCosts.country("US"))
        XCTAssertEqual(us.employerCostPct, 8.0097)
        XCTAssertEqual(us.employerCostPctPrinted, 8)
        XCTAssertEqual(us.employerCostUSDMonth, 800.97)
        XCTAssertNil(us.fxDate)
        XCTAssertEqual(us.fxLocalPerUSD, 1)
    }

    // Every country equals its row of country_summary.csv, split here without
    // parseCSV (the file has no quoted field).
    func testSummaryRowsMatchFile() throws {
        let text = try raw("country_summary")
        XCTAssertFalse(text.contains("\""))
        let lines = text.split(separator: "\n").map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }.filter { !$0.isEmpty }
        let head = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func num(_ s: String) -> Double? { s.isEmpty ? nil : Double(s) }
        for line in lines.dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(f.count, head.count, String(line))
            let v = Dictionary(uniqueKeysWithValues: zip(head, f))
            let c = try XCTUnwrap(EmployerCosts.country(v["iso"]!), String(line))
            XCTAssertEqual(c.name, v["country"]); XCTAssertEqual(c.region, v["region"])
            XCTAssertEqual(c.currency, v["currency"])
            XCTAssertEqual(c.exampleSalaryUSD, Int(v["example_salary_usd"]!))
            XCTAssertEqual(c.exampleRole, v["example_role"]); XCTAssertEqual(c.examplePlace, v["example_place"])
            XCTAssertEqual(c.basicShareOfGross, num(v["basic_share_of_gross"]!))
            XCTAssertEqual(c.employerCostPct, num(v["employer_cost_pct"]!))
            XCTAssertEqual(c.employerCostPctPrinted, num(v["employer_cost_pct_printed"]!))
            XCTAssertEqual(c.totalDeclaredFloor, v["total_declared_floor"] == "true")
            XCTAssertEqual(c.totalDeclaredCeiling, v["total_declared_ceiling"] == "true")
            XCTAssertEqual(c.employerCostUSDMonth, num(v["employer_cost_usd_month"]!))
            XCTAssertEqual(c.totalExcludes, v["total_excludes"])
            XCTAssertEqual(c.fxLocalPerUSD, num(v["fx_local_per_usd"]!))
            XCTAssertEqual(c.fxDate?.description ?? "", v["fx_date"])
            XCTAssertEqual(c.lastReviewed?.description ?? "", v["last_reviewed"])
        }
    }

    // Floor countries: an "at least" figure, flagged on the country and its lines.
    func testFloor() throws {
        let ae = try XCTUnwrap(EmployerCosts.country("AE"))
        XCTAssertTrue(ae.totalDeclaredFloor && !ae.totalDeclaredCeiling)
        for l in EmployerCosts.contributions("AE") { XCTAssertTrue(l.totalDeclaredFloor, l.lineID) }
        XCTAssertEqual(EmployerCosts.country("DE")?.totalDeclaredFloor, false)
        XCTAssertEqual(EmployerCosts.countries().filter(\.totalDeclaredFloor).count, 13)
    }

    // Regions cover every country once.
    func testRegions() {
        var n = 0
        for r in EmployerCosts.regions() {
            let cs = EmployerCosts.countries(inRegion: r)
            XCTAssertFalse(cs.isEmpty, r)
            for c in cs { XCTAssertEqual(c.region, r) }
            n += cs.count
        }
        XCTAssertEqual(n, EmployerCosts.countries().count)
    }

    // Contribution lines, base factors (Mexico's integrated base).
    func testContributions() throws {
        var total = 0
        var factored: [Double: Int] = [:]
        for c in EmployerCosts.countries() {
            let lines = EmployerCosts.contributions(c.iso)
            XCTAssertFalse(lines.isEmpty, c.iso)
            total += lines.count
            for l in lines {
                XCTAssertTrue(l.iso == c.iso && l.currency == c.currency && l.country == c.name, l.lineID)
                XCTAssertTrue(l.totalDeclaredFloor == c.totalDeclaredFloor
                              && l.totalDeclaredCeiling == c.totalDeclaredCeiling, l.lineID)
                switch l.lineType {
                case "contribution":
                    XCTAssertTrue(["gross", "basic", "flat", "band"].contains(l.base) && l.extraKind.isEmpty, l.lineID)
                    XCTAssertEqual(l.base == "flat", l.baseFactor == nil, l.lineID)
                    if let f = l.baseFactor, f != 1 { factored[f, default: 0] += 1 }
                case "statutory_extra":
                    XCTAssertTrue(["percent", "months", "days"].contains(l.extraKind) && l.extraValue != nil
                                  && l.rate == nil && l.baseFactor == nil, l.lineID)
                default:
                    XCTFail("\(c.iso)/\(l.lineID): line_type \(l.lineType)")
                }
                XCTAssertTrue(!l.lineID.isEmpty && !l.sourceURL.isEmpty && l.sourceCheckedAt != nil, l.lineID)
            }
        }
        XCTAssertEqual(total, 544)
        XCTAssertEqual(total, countRecords(try raw("country_contributions")))
        XCTAssertEqual(factored, [1.049315: 9, 1.049867: 1, 1.08: 4, 1.009: 7])
        XCTAssertTrue(EmployerCosts.contributions("xx").isEmpty)
        XCTAssertEqual(EmployerCosts.contributions("mx"), EmployerCosts.contributions("MX"))
    }

    // Assumptions.
    func testAssumptions() {
        var total = 0
        for c in EmployerCosts.countries() {
            for a in EmployerCosts.assumptions(c.iso) {
                XCTAssertTrue(a.iso == c.iso && !a.id.isEmpty && !a.label.isEmpty, c.iso)
                total += 1
            }
        }
        XCTAssertEqual(total, 108)
    }

    func testDayDate() {
        XCTAssertEqual(DayDate("2024-02-29")?.description, "2024-02-29")
        XCTAssertNil(DayDate("2026-02-29"))
        XCTAssertNil(DayDate("2026-1-05"))
        XCTAssertLessThan(DayDate("2026-09-30")!, DayDate("2026-10-01")!)
    }
}
