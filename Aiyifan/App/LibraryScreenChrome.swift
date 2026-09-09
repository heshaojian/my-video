import SwiftUI

enum LibraryScreenChrome {
    static let background = Color(red: 0.055, green: 0.052, blue: 0.073)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
}

private struct LibraryNavigationChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(LibraryScreenChrome.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(.cyan)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func libraryNavigationChrome() -> some View {
        modifier(LibraryNavigationChrome())
    }
}

struct LibraryScreenHeader<Trailing: View>: View {
    let title: String
    let accessibilityIdentifier: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Aiyifan logo")
                .accessibilityIdentifier("\(accessibilityIdentifier)-brandMark")

            VStack(alignment: .leading, spacing: 1) {
                Text("Aiyifan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)

                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(LibraryScreenChrome.primaryText)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }

            Spacer()

            trailing()
        }
    }
}

extension LibraryScreenHeader where Trailing == EmptyView {
    init(title: String, accessibilityIdentifier: String) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        trailing = { EmptyView() }
    }
}
