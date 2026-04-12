import SwiftUI

// MARK: - Главный экран: TabView + баннер подключения

/// Корневой вью с четырьмя вкладками и компактной статусной полосой сверху.
struct ContentView: View {

    private let connection = ConnectionManager.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Баннер статуса подключения — минимальный, прижат к верху
            connectionBanner
            // Основной TabView — занимает всё пространство
            TabView(selection: $selectedTab) {
                TouchpadView()
                    .tabItem {
                        Label("Тачпад", systemImage: "hand.point.up.left")
                    }
                    .tag(0)

                KeyboardView()
                    .tabItem {
                        Label("Клавиатура", systemImage: "keyboard")
                    }
                    .tag(1)

                MediaControlView()
                    .tabItem {
                        Label("Медиа", systemImage: "play.circle")
                    }
                    .tag(2)

                ConnectionView()
                    .tabItem {
                        Label("Связь", systemImage: "wifi")
                    }
                    .tag(3)
            }
            .tint(.white)
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    // MARK: - Баннер подключения (компактный, прижат к верху)

    private var connectionBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connection.isConnected ? .green : .red.opacity(0.7))
                    .frame(width: 6, height: 6)

                if connection.isConnected {
                    Text(connection.connectedServerName ?? "Mac")
                        .font(.caption2.weight(.medium))
                    Image(systemName: connection.activeTransport == .bonjour ? "wifi" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Не подключено")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !connection.isConnected {
                    Button {
                        selectedTab = 3
                    } label: {
                        Text("Подключить")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background {
            Color.black.ignoresSafeArea(.container, edges: .top)
        }
    }
    // MARK: - Настройка внешнего вида TabBar

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        // Убираем разделительную линию над TabBar
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
}
