/// Raised when an embedded CSV file cannot be read.
public struct CSVError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

/// RFC 4180 reader: comma separator, double-quoted fields that may hold
/// commas, doubled quotes and line breaks, LF or CRLF records, optional UTF-8
/// BOM. Blank lines are skipped; every record must have as many fields as the
/// first.
func parseCSV(_ bytes: [UInt8], name: String) throws -> [[String]] {
    let quote = UInt8(ascii: "\""), comma = UInt8(ascii: ","), cr = UInt8(ascii: "\r"), lf = UInt8(ascii: "\n")
    var start = 0
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { start = 3 }

    var recs: [[String]] = []
    var rec: [String] = []
    var buf: [UInt8] = []
    var quoted = false, afterQuote = false, fieldStart = true
    var line = 1, recLine = 1

    func fail(_ msg: String) -> CSVError { CSVError(description: "\(name): line \(line): \(msg)") }

    func endField() {
        rec.append(String(decoding: buf, as: UTF8.self))
        buf.removeAll(keepingCapacity: true)
        quoted = false; afterQuote = false; fieldStart = true
    }

    func endRecord() throws {
        if rec.isEmpty && fieldStart && buf.isEmpty && !afterQuote { return } // blank line
        endField()
        if let first = recs.first, rec.count != first.count {
            line = recLine
            throw fail("expected \(first.count) fields, got \(rec.count)")
        }
        recs.append(rec)
        rec = []
    }

    var i = start
    while i < bytes.count {
        let c = bytes[i]
        defer { i += 1 }
        if quoted {
            if c == quote {
                if i + 1 < bytes.count && bytes[i + 1] == quote {
                    buf.append(quote)
                    i += 1
                } else {
                    quoted = false
                    afterQuote = true
                }
            } else {
                if c == lf { line += 1 }
                buf.append(c)
            }
            continue
        }
        if c == comma { endField(); continue }
        if c == cr || c == lf {
            if c == cr && i + 1 < bytes.count && bytes[i + 1] == lf { i += 1 }
            try endRecord()
            line += 1
            recLine = line
            continue
        }
        if afterQuote { throw fail("extraneous character after a closing quote") }
        if c == quote {
            if !fieldStart { throw fail("bare quote in an unquoted field") }
            quoted = true
            fieldStart = false
            continue
        }
        buf.append(c)
        fieldStart = false
    }
    if quoted { throw fail("unterminated quoted field") }
    try endRecord()
    if recs.isEmpty { throw CSVError(description: "\(name): empty") }
    return recs
}
