import SwiftUI

// MARK: - Медиа-пульт: воспроизведение, громкость, яркость

/// Карточный дизайн (ultraThinMaterial rounded rectangles).
/// Громкость и яркость отображают реальные значения с Mac
/// через connection.currentVolume / connection.currentBrightness.
struct MediaControlView: View {

    private let connection = ConnectionManager.shared
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Локальное состояние (только play/mute — сервер не шлёт их)

    @State private var isPlaying = false
    @State private var isMuted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Управление воспроизведением
                playbackCard

                // Громкость (реальное значение с Mac)
                volumeCard

                // Яркость экрана (реальное значение с Mac)
                brightnessCard

                // Отключение звука
                muteCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black)
        .onAppear {
            // Запрашиваем реальные значения при появлении экрана
            connection.send(.getSystemInfo)
        }
    }

    // MARK: - Воспроизведение

    private var playbackCard: some View {
        VStack(spacing: 16) {

            // Кнопки prev / play / next
            HStack(spacing: 0) {
                // Previous
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

                // Play / Pause
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

                // Next
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
                // Volume Down
                Button {
                    connection.send(.media(action: .volumedown))
                    lightImpact.impactOccurred()
                } label: {
                    Image(systemName: "speaker.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                }

                // Слайдер — отображает реальное значение, управляет дискретными шагами
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)
                        

                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * connection.currentVolume, height: 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = min(1, max(0, value.location.x / geo.size.width))
                                let oldVolume = connection.currentVolume
                                if ratio > oldVolume + 0.03 {
                                    connection.send(.media(action: .volumeup))
                                } else if ratio < oldVolume - 0.03 {
                                    connection.send(.media(action: .volumedown))
                                }
                            }
                    )
                }
                .frame(height: 36)

                // Volume Up
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
                // Brightness Down
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
                            
                            .frame(width: geo.size.width * connection.currentBrightness, height: 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = min(1, max(0, value.location.x / geo.size.width))
                                let oldBrightness = connection.currentBrightness
                                if ratio > oldBrightness + 0.03 {
                                    connection.send(.media(action: .brightnessup))
                                } else if ratio < oldBrightness - 0.03 {
                                    connection.send(.media(action: .brightnessdown))
                                }
                            }
                    )
                }
                .frame(height: 36)

                // Brightness Up
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
            isMuted.toggle()
            connection.send(.media(action: .mute))
            impact.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                Text(isMuted ? "Звук выключен" : "Отключить звук")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isMuted ? .red : .white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isMuted
                    ? AnyShapeStyle(.red.opacity(0.15))
                    : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isMuted ? .red.opacity(0.3) : .clear, lineWidth: 1)
            )
        }
    }
}

#Preview {
    MediaControlView()
        .preferredColorScheme(.dark)
}
