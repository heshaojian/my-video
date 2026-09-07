import AVFoundation
import SwiftUI

struct NativeMiniPlayer: View {
    @ObservedObject var viewModel: NativePlayerViewModel
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    MiniPlayerSurface(player: viewModel.player)
                        .frame(width: 96, height: 54)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(viewModel.episodeTitle ?? "Now Playing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand player for \(viewModel.item.title)")
            .accessibilityIdentifier("expandMiniPlayer")

            Button(action: viewModel.togglePlayback) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("toggleMiniPlayback")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Close player")
            .accessibilityIdentifier("closeMiniPlayer")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 66)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nativeMiniPlayer")
    }
}

private struct MiniPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}
