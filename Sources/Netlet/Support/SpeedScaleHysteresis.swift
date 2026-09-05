import Foundation

struct SpeedScalePair: Equatable, Sendable {
    var downloadIndex = 0
    var uploadIndex = 0
}

struct SpeedScaleHysteresis: Equatable, Sendable {
    private(set) var index = 0
    private var hasNonzeroSample = false

    mutating func update(
        value: Double,
        base: Double,
        maximumIndex: Int
    ) -> Int {
        let safeValue = value.isFinite ? max(0, value) : 0
        guard safeValue > 0 else {
            reset()
            return index
        }

        if !hasNonzeroSample {
            index = naturalIndex(for: safeValue, base: base, maximumIndex: maximumIndex)
            hasNonzeroSample = true
            return index
        }

        while index < maximumIndex,
              safeValue >= threshold(base: base, exponent: index + 1) * 1.05 {
            index += 1
        }

        while index > 0,
              safeValue < threshold(base: base, exponent: index) * 0.95 {
            index -= 1
        }

        return index
    }

    mutating func reset() {
        index = 0
        hasNonzeroSample = false
    }

    private func naturalIndex(for value: Double, base: Double, maximumIndex: Int) -> Int {
        var result = 0
        var boundary = base
        while result < maximumIndex, value >= boundary {
            result += 1
            boundary *= base
        }
        return result
    }

    private func threshold(base: Double, exponent: Int) -> Double {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(1) { result, _ in result * base }
    }
}
