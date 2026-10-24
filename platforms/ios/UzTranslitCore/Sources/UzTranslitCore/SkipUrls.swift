// SPEC §5.6: URL / e-mail / @handle protection. The reference tokenises with the JavaScript expression
//   /(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g
// whose classes are JavaScript's: \s is the fixed set marked F_SPACE, \w is [A-Za-z0-9_]. This index scanner finds
// exactly the matches of that expression (as core/wasm/assembly/index.ts does): positions are tried left to right,
// the alternatives in order; the text between tokens is converted slice by slice, tokens are copied unchanged.

/// Length of an `http://`, `https://` or `www.` prefix at `p`, or 0.
func urlPrefix(_ text: [UInt16], _ p: Int) -> Int {
    let n = text.count
    if p + 4 <= n && text[p] == 0x77 && text[p + 1] == 0x77 && text[p + 2] == 0x77 && text[p + 3] == 0x2E { return 4 } // www.
    if p + 7 <= n && text[p] == 0x68 && text[p + 1] == 0x74 && text[p + 2] == 0x74 && text[p + 3] == 0x70 { // http
        var q = p + 4
        if text[q] == 0x73 { q += 1 } // s
        if q + 3 <= n && text[q] == 0x3A && text[q + 1] == 0x2F && text[q + 2] == 0x2F { return q + 3 - p } // ://
    }
    return 0
}

func withSkips(_ text: [UInt16], _ fn: ([UInt16]) -> [UInt16]) -> [UInt16] {
    let n = text.count
    var out: [UInt16] = []
    out.reserveCapacity(n + n / 4)
    var last = 0, p = 0
    var runEnd = -1, runAt = -1
    while p < n {
        let c = Int(text[p])
        if isSpace(c) { p += 1; continue }
        if p >= runEnd {
            // a new run of non-space characters: \S+@\S+\.\S+ matches from p to the end of the run iff some '@' at
            // x >= p+1 is followed by a '.' at y >= x+2 with y <= runEnd-2. The last such '@' stays valid for every
            // later start inside the run.
            runEnd = p
            while runEnd < n && !isSpace(Int(text[runEnd])) { runEnd += 1 }
            var dot = -1
            var k = runEnd - 2
            while k >= p {
                if text[k] == 0x2E { dot = k; break }
                k -= 1
            }
            runAt = -1
            k = dot - 2
            while k >= p {
                if text[k] == 0x40 { runAt = k; break }
                k -= 1
            }
        }
        var mEnd = -1
        let pre = urlPrefix(text, p)
        if pre > 0 && p + pre < runEnd { mEnd = runEnd } // (https?:\/\/|www\.)\S+
        else if runAt >= p + 1 { mEnd = runEnd } // \S+@\S+\.\S+
        else if c == 0x40 && p + 1 < n && isWordChar(Int(text[p + 1])) { // @\w+
            mEnd = p + 2
            while mEnd < n && isWordChar(Int(text[mEnd])) { mEnd += 1 }
        }
        if mEnd < 0 { p += 1; continue }
        out.append(contentsOf: fn(Array(text[last..<p])))
        out.append(contentsOf: text[p..<mEnd])
        last = mEnd
        p = mEnd
    }
    out.append(contentsOf: fn(Array(text[last..<n])))
    return out
}
