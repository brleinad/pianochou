extension Score {
    /// The bars from `first` to `last` (indices into the written measures) as they are played: repeats and
    /// endings followed, laid out one after another in a new score, so a run can follow it straight through.
    /// Printed bar numbers stay; repeat signs and endings go.
    ///
    /// Playing starts the first time `first` comes up. If the music stays within `first...last` until it
    /// reaches `last`, it stops the last time `last` comes up before leaving the range (a range inside a
    /// repeat is played once; a range over a repeat includes it). Otherwise it follows the music, wherever
    /// it goes, until `last`.
    public func playing(from first: Int, to last: Int) -> Score {
        let order = playedOrder
        guard let start = order.firstIndex(of: first) else { return self }
        var end: Int?
        var p = start
        while p < order.count, (first...last).contains(order[p]) {
            if order[p] == last { end = p }
            p += 1
        }
        if end == nil { end = order[start...].firstIndex(of: last) }
        let slice = Array(order[start...(end ?? start)])

        var out = self
        for (i, part) in parts.enumerated() {
            var start = Rational.zero
            out.parts[i].measures = slice.enumerated().map { position, m in
                var measure = part.measures[m]
                measure.index = position
                measure.start = start
                measure.startRepeat = false
                measure.endRepeatTimes = nil
                measure.endingNumbers = nil
                start = start + measure.duration
                return measure
            }
        }
        out.playedOrder = Array(slice.indices)
        return out
    }
}
