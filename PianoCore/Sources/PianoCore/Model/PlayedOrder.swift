/// Unfolds repeats and volta endings into the order measures are played.
/// Handles forward/backward repeats (with `times`) and numbered endings.
/// D.C., D.S. and coda jumps are not handled yet.
enum PlayedOrder {
    static func unfold(_ measures: [Measure]) -> [Int] {
        var order: [Int] = []
        var index = 0
        var pass = 1
        var repeatStart = 0
        var jumpsTaken: [Int: Int] = [:]
        var arrivedByJump = false
        // A malformed score must not loop forever.
        let limit = measures.count * 32

        while index < measures.count, order.count < limit {
            let measure = measures[index]
            if measure.startRepeat && !arrivedByJump {
                repeatStart = index
                pass = 1
            }
            arrivedByJump = false

            if let endings = measure.endingNumbers, !endings.contains(pass) {
                index += 1
                continue
            }
            order.append(index)

            if let times = measure.endRepeatTimes {
                let taken = jumpsTaken[index, default: 0]
                if taken < times - 1 {
                    jumpsTaken[index] = taken + 1
                    pass += 1
                    index = repeatStart
                    arrivedByJump = true
                    continue
                }
                repeatStart = index + 1
                pass = 1
            } else if measure.endingNumbers != nil,
                      index + 1 == measures.count || measures[index + 1].endingNumbers == nil {
                // The last ending is done: what follows is a fresh section.
                repeatStart = index + 1
                pass = 1
            }
            index += 1
        }
        return order
    }
}
