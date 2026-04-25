import SwiftUI

// MARK: - Медиа-пульт: воспроизведение, громкость, яркость
/// Карточный дизайн (ultraThinMaterial rounded rectangles).
/// Громкость и яркость отображают реальные значения с Mac
/// через connection.currentVolume / connection.currentBrightness.
struct MediaControlView: View {
    private let connection = ConnectionManager.shared
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Локальное состояние
    @State private var isPlaying = false

    // Локальные draft-значения для плавного UI во время drag
    @State private var draftVolume: Double?
    @State private var draftBrightness: Double?
    
    // Последние отправленные значения для синхронного сброса draft
    @State private var lastSentVolume: Double?
    @State private var lastSentBrightness: Double?
    
    // Debounce-задачи, чтобы не заспамить сеть
    @State private var volumeTask: Task<Void, Never>?
    @State private var brightnessTask: Task<Void, Never>?

    private var displayedVolume: Double {
        if connection.isMuted { return 0.0 }
        return draftVolume ?? connection.currentVolume
    }

    private var displayedBrightness: Double {
        draftBrightness ?? connection.currentBrightness
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                playbackCard
                volumeCard
                brightnessCard
                muteCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black)
        .onAppear {
            connection.send(.getSystemInfo)
        }
        .onDisappear {
            volumeTask?.cancel()
            brightnessTask?.cancel()
        }
        .onChange(of: connection.currentVolume) { _, newValue in
            if let sent = lastSentVolume, abs(sent - newValue) < 0.02 {
                draftVolume = nil
                lastSentVolume = nil
            }
        }
        .onChange(of: connection.currentBrightness) { _, newValue in
            if let sent = lastSentBrightness, abs(sent - newValue) < 0.02 {
                draftBrightness = nil
                lastSentBrightness = nil
            }
        }
    }

    // MARK: - Воспроизведение
    private var playbackCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                Button {
                    connection.send(.media(action: .previous))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }

                Button {
                    isPlaying.toggle()
                    connection.send(.media(action: .playpause))
                    impact.impactOccurred()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }

                Button {
                    connection.send(.media(action: .next))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Громкость
    private var volumeCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    connection.send(.media(action: .volumedown))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "speaker.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * displayedVolume, height: 6)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = normalizedRatio(value.location.x, width: geo.size.width)
                                draftVolume = ratio
                                sendVolumeDebounced(ratio)
                            }
                            .onEnded { value in
                                let ratio = normalizedRatio(value.location.x, width: geo.size.width)
                                draftVolume = ratio
                                lastSentVolume = ratio
                                volumeTask?.cancel()
                                connection.send(.setVolume(value: ratio))
                            }
                    )
                }
                .frame(height: 36)

                Button {
                    connection.send(.media(action: .volumeup))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Яркость экрана
    private var brightnessCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    connection.send(.media(action: .brightnessdown))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "sun.min")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * displayedBrightness, height: 6)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = normalizedRatio(value.location.x, width: geo.size.width)
                                draftBrightness = ratio
                                sendBrightnessDebounced(ratio)
                            }
                            .onEnded { value in
                                let ratio = normalizedRatio(value.location.x, width: geo.size.width)
                                draftBrightness = ratio
                                lastSentBrightness = ratio
                                brightnessTask?.cancel()
                                connection.send(.setBrightness(value: ratio))
                            }
                    )
                }
                .frame(height: 36)

                Button {
                    connection.send(.media(action: .brightnessup))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "sun.max.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Отключение звука
    private var muteCard: some View {
        Button {
            let newValue = !connection.isMuted
            connection.send(.setMute(enabled: newValue))
            impact.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: connection.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)

                Text(connection.isMuted ? "Звук выключен" : "Отключить звук")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(connection.isMuted ? .red : .white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                connection.isMuted
                ? AnyShapeStyle(.red.opacity(0.15))
                : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(connection.isMuted ? .red.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers
    private func normalizedRatio(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }

    private func sendVolumeDebounced(_ value: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connection.send(.setVolume(value: value))
            }
        }
    }

    private func sendBrightnessDebounced(_ value: Double) {
        brightnessTask?.cancel()
        brightnessTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                connection.send(.setBrightness(value: value))
            }
        }
    }
}

#Preview {
    MediaControlView()
        .preferredColorScheme(.dark)
}
