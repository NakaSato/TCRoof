import Foundation

/// Works out one sheet's formulas from its cells, so a file the app changed carries results a viewer shows without
/// recalculating (iOS Quick Look, Drive's preview). It knows what the station plan workbooks use: `+ - * / ^ &`,
/// comparisons, `IF`, `SUM`, `SUMIF`, `MINIFS`, `MAXIFS`, `WEEKNUM`, `DATE`, and shared formulas. A formula outside
/// that (another sheet, another function) is `unknown`, and so is everything that reads it: those cells keep the
/// result Excel saved.
struct SheetFormulas {
    enum Value: Equatable {
        case number(Double), text(String), bool(Bool), empty, error(String)
        /// Not worked out; the cell keeps its saved result.
        case unknown
    }

    struct Pos: Hashable { var col: Int, row: Int }

    struct Ref: Equatable { var col: Int, row: Int, absCol: Bool, absRow: Bool }

    indirect enum Expr: Equatable {
        case value(Value)
        case ref(Ref)
        case range(Ref, Ref)
        case negate(Expr)
        case percent(Expr)
        case binary(String, Expr, Expr)
        case call(String, [Expr])
        case unsupported
    }

    /// A formula cell: its expression, and how far it sits from the cell the formula was written for (shared formulas).
    struct Formula { var expr: Expr; var dr: Int; var dc: Int }

    private(set) var formulas: [Pos: Formula] = [:]
    private var inputs: [Pos: Value] = [:]
    private var memo: [Pos: Value] = [:]
    private var visiting: Set<Pos> = []
    let calendar: Calendar

    init(calendar: Calendar) { self.calendar = calendar }

    /// A value cell (number, text, bool) or an empty one.
    mutating func setInput(_ p: Pos, _ v: Value) {
        inputs[p] = v
        formulas[p] = nil
        memo = [:]
    }

    mutating func setFormula(_ p: Pos, text: String, master: Pos) {
        formulas[p] = Formula(expr: Self.parse(text), dr: p.row - master.row, dc: p.col - master.col)
        inputs[p] = nil
        memo = [:]
    }

    /// Shares the parsed formula of `master` with a cell of its `ref` range.
    mutating func share(_ p: Pos, from master: Pos) {
        guard let f = formulas[master] else { return }
        formulas[p] = Formula(expr: f.expr, dr: p.row - master.row + f.dr, dc: p.col - master.col + f.dc)
        inputs[p] = nil
        memo = [:]
    }

    mutating func value(_ p: Pos) -> Value {
        if let v = memo[p] { return v }
        guard let f = formulas[p] else { return inputs[p] ?? .empty }
        // a circular reference isn't worked out
        guard visiting.insert(p).inserted else { return .unknown }
        let v = eval(f.expr, f)
        visiting.remove(p)
        memo[p] = v
        return v
    }

    // MARK: evaluation

    private func shift(_ r: Ref, _ f: Formula) -> Pos {
        Pos(col: r.absCol ? r.col : r.col + f.dc, row: r.absRow ? r.row : r.row + f.dr)
    }

    private mutating func eval(_ e: Expr, _ f: Formula) -> Value {
        switch e {
        case .value(let v): return v
        case .ref(let r): return value(shift(r, f))
        case .range: return .error("#VALUE!")
        case .unsupported: return .unknown
        case .negate(let x):
            return arith(eval(x, f), .number(-1), *)
        case .percent(let x):
            return arith(eval(x, f), .number(100), /)
        case .binary(let op, let a, let b):
            let x = eval(a, f), y = eval(b, f)
            switch op {
            case "+": return arith(x, y, +)
            case "-": return arith(x, y, -)
            case "*": return arith(x, y, *)
            case "/":
                if case .number(let d) = Self.number(y), d == 0 { return x == .unknown ? .unknown : .error("#DIV/0!") }
                return arith(x, y, /)
            case "^": return arith(x, y) { pow($0, $1) }
            case "&":
                if let bad = Self.bad(x, y) { return bad }
                return .text(Self.text(x) + Self.text(y))
            default: return compare(op, x, y)
            }
        case .call(let name, let args): return call(name, args, f)
        }
    }

    /// The first unknown, else the first error, of the operands.
    private static func bad(_ xs: Value...) -> Value? {
        if xs.contains(.unknown) { return .unknown }
        return xs.first { if case .error = $0 { return true } else { return false } }
    }

    private func arith(_ x: Value, _ y: Value, _ op: (Double, Double) -> Double) -> Value {
        if let bad = Self.bad(x, y) { return bad }
        guard case .number(let a) = Self.number(x), case .number(let b) = Self.number(y) else { return .error("#VALUE!") }
        let r = op(a, b)
        return r.isFinite ? .number(r) : .error("#NUM!")
    }

    /// A value as a number for arithmetic: empty is 0, TRUE 1, numeric text its number.
    static func number(_ v: Value) -> Value {
        switch v {
        case .number: return v
        case .empty: return .number(0)
        case .bool(let b): return .number(b ? 1 : 0)
        case .text(let t): return Double(t.trimmingCharacters(in: .whitespaces)).map { .number($0) } ?? .error("#VALUE!")
        default: return v
        }
    }

    static func text(_ v: Value) -> String {
        switch v {
        case .number(let n): return IECExcel.number(n)
        case .text(let t): return t
        case .bool(let b): return b ? "TRUE" : "FALSE"
        default: return ""
        }
    }

    /// Excel's order: numbers < text < booleans; text compares without case; empty is 0 or "".
    private func compare(_ op: String, _ x: Value, _ y: Value) -> Value {
        if let bad = Self.bad(x, y) { return bad }
        func rank(_ v: Value) -> Int { switch v { case .text: 1; case .bool: 2; default: 0 } }
        var a = x, b = y
        if a == .empty { a = rank(b) == 1 ? .text("") : rank(b) == 2 ? .bool(false) : .number(0) }
        if b == .empty { b = rank(a) == 1 ? .text("") : rank(a) == 2 ? .bool(false) : .number(0) }
        let c: Int
        switch (a, b) {
        case let (.number(p), .number(q)): c = p < q ? -1 : p > q ? 1 : 0
        case let (.text(p), .text(q)):
            let r = p.compare(q, options: .caseInsensitive)
            c = r == .orderedAscending ? -1 : r == .orderedDescending ? 1 : 0
        case let (.bool(p), .bool(q)): c = p == q ? 0 : (p ? 1 : -1)
        default: c = rank(a) < rank(b) ? -1 : 1
        }
        switch op {
        case "=": return .bool(c == 0)
        case "<>": return .bool(c != 0)
        case "<": return .bool(c < 0)
        case ">": return .bool(c > 0)
        case "<=": return .bool(c <= 0)
        case ">=": return .bool(c >= 0)
        default: return .unknown
        }
    }

    /// The cells of a range argument, row by row.
    private func cells(_ e: Expr, _ f: Formula) -> [Pos]? {
        switch e {
        case .ref(let r): return [shift(r, f)]
        case .range(let a, let b):
            let p = shift(a, f), q = shift(b, f)
            var out: [Pos] = []
            for row in min(p.row, q.row)...max(p.row, q.row) {
                for col in min(p.col, q.col)...max(p.col, q.col) { out.append(Pos(col: col, row: row)) }
            }
            return out
        default: return nil
        }
    }

    private mutating func call(_ raw: String, _ args: [Expr], _ f: Formula) -> Value {
        let name = raw.uppercased().replacingOccurrences(of: "_XLFN.", with: "")
        switch name {
        case "IF":
            guard (2...3).contains(args.count) else { return .unknown }
            let c = eval(args[0], f)
            if let bad = Self.bad(c) { return bad }
            let yes: Bool
            switch Self.number(c) {
            case .number(let n): yes = n != 0
            default: return .error("#VALUE!")
            }
            if yes { return eval(args[1], f) }
            return args.count == 3 ? eval(args[2], f) : .bool(false)

        case "SUM":
            var total = 0.0
            for a in args {
                if let ps = cells(a, f) {
                    for p in ps {
                        let v = value(p)
                        if let bad = Self.bad(v) { return bad }
                        if case .number(let n) = v { total += n }
                    }
                } else {
                    let v = eval(a, f)
                    if let bad = Self.bad(v) { return bad }
                    guard case .number(let n) = Self.number(v) else { return .error("#VALUE!") }
                    total += n
                }
            }
            return .number(total)

        case "SUMIF":
            guard (2...3).contains(args.count), let range = cells(args[0], f) else { return .unknown }
            let crit = eval(args[1], f)
            if let bad = Self.bad(crit) { return bad }
            let sum = args.count == 3 ? (cells(args[2], f) ?? []) : range
            guard sum.count >= 1 else { return .unknown }
            // the sum range takes the criteria range's shape from its first cell
            let origin = range[0], start = sum[0]
            var total = 0.0
            for p in range {
                let v = value(p)
                if v == .unknown { return .unknown }
                guard Self.matches(v, crit) else { continue }
                let s = value(Pos(col: start.col + p.col - origin.col, row: start.row + p.row - origin.row))
                if let bad = Self.bad(s) { return bad }
                if case .number(let n) = s { total += n }
            }
            return .number(total)

        case "MINIFS", "MAXIFS":
            guard args.count >= 3, args.count % 2 == 1, let target = cells(args[0], f) else { return .unknown }
            var pairs: [([Pos], Value)] = []
            for i in stride(from: 1, to: args.count, by: 2) {
                guard let r = cells(args[i], f), r.count == target.count else { return .error("#VALUE!") }
                let c = eval(args[i + 1], f)
                if let bad = Self.bad(c) { return bad }
                pairs.append((r, c))
            }
            var found: [Double] = []
            for (i, p) in target.enumerated() {
                var ok = true
                for (r, c) in pairs {
                    let v = value(r[i])
                    if v == .unknown { return .unknown }
                    if !Self.matches(v, c) { ok = false; break }
                }
                guard ok else { continue }
                let v = value(p)
                if let bad = Self.bad(v) { return bad }
                if case .number(let n) = v { found.append(n) }
            }
            return .number((name == "MINIFS" ? found.min() : found.max()) ?? 0)

        case "DATE":
            guard args.count == 3 else { return .unknown }
            var n: [Int] = []
            for a in args {
                let v = eval(a, f)
                if let bad = Self.bad(v) { return bad }
                guard case .number(let x) = Self.number(v) else { return .error("#VALUE!") }
                n.append(Int(x.rounded(.down)))
            }
            // months and days past their ends roll over, as in Excel
            guard let first = calendar.date(from: DateComponents(year: n[0], month: 1, day: 1)),
                  let month = calendar.date(byAdding: .month, value: n[1] - 1, to: first),
                  let day = calendar.date(byAdding: .day, value: n[2] - 1, to: month) else { return .error("#NUM!") }
            return .number(MPWorkbook.Sheet.serial(day, calendar))

        case "WEEKNUM":
            guard (1...2).contains(args.count) else { return .unknown }
            if args.count == 2 {
                let t = eval(args[1], f)
                if let bad = Self.bad(t) { return bad }
                guard case .number(1) = Self.number(t) else { return .unknown }
            }
            let v = eval(args[0], f)
            if let bad = Self.bad(v) { return bad }
            guard case .number(let s) = Self.number(v) else { return .error("#VALUE!") }
            // Excel's day 0 (0 ม.ค. 1900) is in week 0
            guard s >= 1 else { return .number(0) }
            return .number(Double(Self.weekNumber(MPWorkbook.Sheet.date(s, calendar), calendar)))

        default:
            return .unknown
        }
    }

    /// `WEEKNUM(date)` (weeks start on Sunday, the week holding 1 January is week 1).
    static func weekNumber(_ d: Date, _ cal: Calendar) -> Int {
        let year = cal.component(.year, from: d)
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let offset = cal.component(.weekday, from: jan1) - 1          // 0 = Sunday
        let day = cal.dateComponents([.day], from: jan1, to: cal.startOfDay(for: d)).day ?? 0
        return (day + offset) / 7 + 1
    }

    /// A `SUMIF` / `MINIFS` criterion: `"Plan"`, `">0"`, `"<>x"`, or a value to equal.
    static func matches(_ v: Value, _ crit: Value) -> Bool {
        var op = "=", operand: Value = crit
        if case .text(let t) = crit {
            for o in ["<=", ">=", "<>", "<", ">", "="] where t.hasPrefix(o) {
                op = o
                let rest = String(t.dropFirst(o.count))
                operand = Double(rest).map { .number($0) } ?? .text(rest)
                break
            }
            if op == "=", let n = Double(t) { operand = .number(n) }
        }
        switch (v, operand) {
        case let (.number(a), .number(b)):
            switch op {
            case "=": return a == b
            case "<>": return a != b
            case "<": return a < b
            case ">": return a > b
            case "<=": return a <= b
            default: return a >= b
            }
        case let (.text(a), .text(b)):
            let same = a.caseInsensitiveCompare(b) == .orderedSame
            return op == "<>" ? !same : op == "=" ? same : false
        case (.empty, .text(let b)):
            return op == "<>" ? !b.isEmpty : op == "=" ? b.isEmpty : false
        case (.empty, _):
            return op == "<>"
        default:
            return op == "<>"
        }
    }

    // MARK: parsing

    static func parse(_ formula: String) -> Expr {
        var p = Parser(tokens: tokenize(formula))
        guard let tokens = p.tokens, !tokens.isEmpty else { return .unsupported }
        let e = p.comparison()
        return p.at == tokens.count ? e : .unsupported
    }

    enum Token: Equatable { case number(Double), text(String), name(String), error(String), op(String) }

    static func tokenize(_ s: String) -> [Token]? {
        let cs = Array(s.hasPrefix("=") ? String(s.dropFirst()) : s)
        var out: [Token] = [], i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " || c == "\n" { i += 1; continue }
            if c.isNumber || (c == "." && i + 1 < cs.count && cs[i + 1].isNumber) {
                var j = i
                while j < cs.count, cs[j].isNumber || cs[j] == "." { j += 1 }
                if j < cs.count, cs[j] == "E" || cs[j] == "e" {
                    var k = j + 1
                    if k < cs.count, cs[k] == "+" || cs[k] == "-" { k += 1 }
                    if k < cs.count, cs[k].isNumber { j = k; while j < cs.count, cs[j].isNumber { j += 1 } }
                }
                // a row range like 1:3 isn't a number
                guard let n = Double(String(cs[i..<j])) else { return nil }
                out.append(.number(n)); i = j; continue
            }
            if c == "\"" {
                var t = "", j = i + 1
                while j < cs.count {
                    if cs[j] == "\"" {
                        if j + 1 < cs.count, cs[j + 1] == "\"" { t.append("\""); j += 2; continue }
                        break
                    }
                    t.append(cs[j]); j += 1
                }
                guard j < cs.count else { return nil }
                out.append(.text(t)); i = j + 1; continue
            }
            if c == "#" {
                var j = i + 1
                while j < cs.count, cs[j].isLetter || cs[j].isNumber || cs[j] == "/" || cs[j] == "!" || cs[j] == "?" {
                    j += 1
                    if cs[j - 1] == "!" || cs[j - 1] == "?" { break }
                }
                out.append(.error(String(cs[i..<j]))); i = j; continue
            }
            if c.isLetter || c == "$" || c == "_" {
                var j = i
                while j < cs.count, cs[j].isLetter || cs[j].isNumber || cs[j] == "$" || cs[j] == "_" || cs[j] == "." { j += 1 }
                out.append(.name(String(cs[i..<j]))); i = j; continue
            }
            if c == "'" || c == "!" || c == "[" || c == "{" { return nil }   // another sheet, a table, an array: not here
            let two = i + 1 < cs.count ? String(cs[i...i + 1]) : ""
            if ["<=", ">=", "<>"].contains(two) { out.append(.op(two)); i += 2; continue }
            if "+-*/^&=<>(),:%".contains(c) { out.append(.op(String(c))); i += 1; continue }
            return nil
        }
        return out
    }

    struct Parser {
        let tokens: [Token]?
        var at = 0
        init(tokens: [Token]?) { self.tokens = tokens }

        private var peek: Token? { tokens.flatMap { at < $0.count ? $0[at] : nil } }
        private mutating func take() -> Token? { defer { at += 1 }; return peek }
        private mutating func takeOp(_ ops: [String]) -> String? {
            if case .op(let o)? = peek, ops.contains(o) { at += 1; return o }
            return nil
        }

        mutating func comparison() -> Expr {
            var e = concat()
            while let o = takeOp(["=", "<>", "<", ">", "<=", ">="]) { e = .binary(o, e, concat()) }
            return e
        }
        mutating func concat() -> Expr {
            var e = additive()
            while let o = takeOp(["&"]) { e = .binary(o, e, additive()) }
            return e
        }
        mutating func additive() -> Expr {
            var e = term()
            while let o = takeOp(["+", "-"]) { e = .binary(o, e, term()) }
            return e
        }
        mutating func term() -> Expr {
            var e = power()
            while let o = takeOp(["*", "/"]) { e = .binary(o, e, power()) }
            return e
        }
        mutating func power() -> Expr {
            var e = unary()
            while let o = takeOp(["^"]) { e = .binary(o, e, unary()) }
            return e
        }
        mutating func unary() -> Expr {
            if takeOp(["-"]) != nil { return .negate(unary()) }
            if takeOp(["+"]) != nil { return unary() }
            var e = primary()
            while takeOp(["%"]) != nil { e = .percent(e) }
            return e
        }
        mutating func primary() -> Expr {
            guard let t = take() else { return .unsupported }
            switch t {
            case .number(let n): return .value(.number(n))
            case .text(let s): return .value(.text(s))
            case .error(let s): return .value(.error(s))
            case .op("("):
                let e = comparison()
                return takeOp([")"]) != nil ? e : .unsupported
            case .name(let n):
                if takeOp(["("]) != nil {
                    var args: [Expr] = []
                    if takeOp([")"]) != nil { return .call(n, args) }
                    repeat { args.append(comparison()) } while takeOp([","]) != nil
                    return takeOp([")"]) != nil ? .call(n, args) : .unsupported
                }
                if n.uppercased() == "TRUE" { return .value(.bool(true)) }
                if n.uppercased() == "FALSE" { return .value(.bool(false)) }
                guard let a = Self.ref(n) else { return .unsupported }
                if takeOp([":"]) != nil {
                    guard case .name(let m)? = take(), let b = Self.ref(m) else { return .unsupported }
                    return .range(a, b)
                }
                return .ref(a)
            default: return .unsupported
            }
        }

        /// `$E13`, `L$10`, `BX29`.
        static func ref(_ s: String) -> Ref? {
            let cs = Array(s)
            var i = 0, absCol = false, absRow = false
            if i < cs.count, cs[i] == "$" { absCol = true; i += 1 }
            var col = 0, letters = 0
            while i < cs.count, let a = cs[i].asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a) - 64; i += 1; letters += 1 }
            if i < cs.count, cs[i] == "$" { absRow = true; i += 1 }
            guard (1...3).contains(letters), i < cs.count, let row = Int(String(cs[i...])), row > 0 else { return nil }
            return Ref(col: col - 1, row: row, absCol: absCol, absRow: absRow)
        }
    }
}
