import SwiftUI

struct CastMiniController: View {
    @ObservedObject var manager: GoogleCastManager
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.snapshot.title.isEmpty ? "Casting" : manager.snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(receiverName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: manager.togglePlayback) {
                Image(systemName: manager.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel(manager.snapshot.isPlaying ? "Pause Cast" : "Resume Cast")
            .accessibilityIdentifier("toggleCastPlaybackMini")

            Button(action: onExpand) {
                Image(systemName: "chevron.up")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Expand Cast controls")
            .accessibilityIdentifier("expandCastController")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 64)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("castMiniController")
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: manager.snapshot.artworkURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "tv.fill")
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var receiverName: String {
        manager.snapshot.receiverName.isEmpty ? "Cast device" : manager.snapshot.receiverName
    }
}

struct CastExpandedController: View {
    @ObservedObject var manager: GoogleCastManager
    @Environment(\.dismiss) private var dismiss
    @State private var scrubPosition = 0.0
    @State private var isScrubbing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                artwork

                VStack(spacing: 5) {
                    Text(manager.snapshot.title.isEmpty ? "Casting" : manager.snapshot.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let subtitle = manager.snapshot.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label(receiverName, systemImage: "tv")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }

                VStack(spacing: 6) {
                    Slider(
                        value: $scrubPosition,
                        in: 0...max(manager.snapshot.duration, 1),
                        onEditingChanged: handleScrubbing
                    )
                    .disabled(manager.snapshot.duration <= 0)
                    .accessibilityLabel("Cast position")
                    .accessibilityIdentifier("castPosition")

                    HStack {
                        Text(formatTime(scrubPosition))
                        Spacer()
                        Text("-\(formatTime(max(0, manager.snapshot.duration - scrubPosition)))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 28) {
                    controlButton(
                        systemName: "gobackward.15",
                        label: "Skip Cast backward 15 seconds",
                        identifier: "skipCastBackward"
                    ) {
                        manager.skip(by: -15)
                    }

                    controlButton(
                        systemName: manager.snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                        label: manager.snapshot.isPlaying ? "Pause Cast" : "Resume Cast",
                        identifier: "toggleCastPlayback",
                        size: 54
                    ) {
                        manager.togglePlayback()
                    }

                    controlButton(
                        systemName: "goforward.15",
                        label: "Skip Cast forward 15 seconds",
                        identifier: "skipCastForward"
                    ) {
                        manager.skip(by: 15)
                    }
                }

                HStack(spacing: 24) {
                    controlButton(
                        systemName: manager.snapshot.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: manager.snapshot.isMuted ? "Unmute Cast" : "Mute Cast",
                        identifier: "toggleCastMute"
                    ) {
                        manager.toggleMute()
                    }
                    .disabled(manager.snapshot.isAdvertisement)

                    if manager.snapshot.hasError {
                        controlButton(
                            systemName: "arrow.clockwise",
                            label: "Retry Cast",
                            identifier: "retryCast"
                        ) {
                            manager.retry()
                        }
                    }
                }

                if manager.snapshot.isAdvertisement {
                    Label("Advertisement muted", systemImage: "speaker.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let errorMessage = manager.snapshot.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    manager.stopCasting()
                    dismiss()
                } label: {
                    Label("Stop Casting", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopCasting")
            }
            .padding(20)
            .navigationTitle("Cast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                scrubPosition = manager.snapshot.position
            }
            .onChange(of: manager.snapshot.position) { _, position in
                if !isScrubbing {
                    scrubPosition = position
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("castExpandedController")
        }
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: manager.snapshot.artworkURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "tv.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var receiverName: String {
        manager.snapshot.receiverName.isEmpty ? "Cast device" : manager.snapshot.receiverName
    }

    private func controlButton(
        systemName: String,
        label: String,
        identifier: String,
        size: CGFloat = 42,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size == 54 ? 44 : 24))
                .frame(width: size, height: size)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func handleScrubbing(_ editing: Bool) {
        isScrubbing = editing
        if !editing {
            manager.seek(to: scrubPosition)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
