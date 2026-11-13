/// Display rounding for weights. Math is always done unrounded. See docs/SPEC.md §3.4.
public enum WeightDisplay {
    /// Weights under this many grams show to 0.1 g.
    public static let fineThreshold = 20.0

    /// Whole grams, or 0.1 g when `precise` (salt, adjuncts) or under 20 g.
    public static func rounded(_ grams: Double, precise: Bool = false) -> Double {
        if precise || grams < fineThreshold {
            return (grams * 10).rounded() / 10
        }
        return grams.rounded()
    }
}
