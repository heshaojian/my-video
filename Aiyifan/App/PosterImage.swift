import SwiftUI

struct PosterImage: View {
    let item: AiyifanItem

    var body: some View {
        AsyncImage(url: item.thumbnailURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.06))
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
