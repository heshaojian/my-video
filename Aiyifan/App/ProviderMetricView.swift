import SwiftUI

enum CompactMetricFormatter {
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 {
            return compact(Double(value) / 1_000_000, suffix: "M")
        }
        if value >= 1_000 {
            return compact(Double(value) / 1_000, suffix: "K")
        }
        return String(value)
    }

    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\(suffix)"
        }
        return String(format: "%.1f%@", rounded, suffix)
    }
}

struct ProviderScoreBadge: View {
    let score: Double

    var body: some View {
        Label(CompactMetricFormatter.score(score), systemImage: "star.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
