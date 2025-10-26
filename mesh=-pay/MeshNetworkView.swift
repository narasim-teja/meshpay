import SwiftUI
import MultipeerConnectivity

struct MeshNetworkView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var meshManager: MeshNetworkManager
    @State private var showTestMessage = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Status Card
                        statusCard

                        // Network Visualization
                        networkVisualization

                        // Connected Peers List
                        peersListSection

                        // Test Controls
                        testControlsSection

                        // Recent Messages
                        messagesSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Mesh Network")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Status")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 15) {
                        StatusIndicator(
                            icon: "wifi.circle.fill",
                            label: "Mesh",
                            isActive: meshManager.isBrowsing,
                            color: .blue
                        )

                        StatusIndicator(
                            icon: "antenna.radiowaves.left.and.right",
                            label: "Broadcasting",
                            isActive: meshManager.isAdvertising,
                            color: .green
                        )

                        StatusIndicator(
                            icon: "network",
                            label: "Internet",
                            isActive: meshManager.hasInternet,
                            color: .orange
                        )
                    }
                }

                Spacer()

                // Peer count badge
                VStack {
                    Text("\(meshManager.connectedPeers.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Peers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    // MARK: - Network Visualization
    private var networkVisualization: some View {
        VStack(spacing: 10) {
            Text("Network Map")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                // Canvas background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                GeometryReader { geometry in
                    let centerX = geometry.size.width / 2
                    let centerY = geometry.size.height / 2
                    let radius: CGFloat = min(geometry.size.width, geometry.size.height) / 3

                    ZStack {
                        // Connection lines from center to peers
                        ForEach(Array(meshManager.connectedPeers.enumerated()), id: \.element.id) { index, peer in
                            let angle = (2 * .pi / Double(meshManager.connectedPeers.count)) * Double(index)
                            let peerX = centerX + radius * cos(angle)
                            let peerY = centerY + radius * sin(angle)

                            // Animated connection line
                            Path { path in
                                path.move(to: CGPoint(x: centerX, y: centerY))
                                path.addLine(to: CGPoint(x: peerX, y: peerY))
                            }
                            .stroke(
                                peer.hasInternet ? Color.green : Color.blue,
                                style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                            )
                            .animation(.easeInOut(duration: 1.0).repeatForever(), value: meshManager.connectedPeers.count)
                        }

                        // Center node (this device)
                        VStack {
                            ZStack {
                                Circle()
                                    .fill(meshManager.hasInternet ? Color.green : Color.orange)
                                    .frame(width: 60, height: 60)
                                    .shadow(color: meshManager.hasInternet ? .green.opacity(0.5) : .orange.opacity(0.5), radius: 10)

                                Image(systemName: meshManager.hasInternet ? "iphone.radiowaves.left.and.right" : "iphone")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }

                            Text("You")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .position(x: centerX, y: centerY)

                        // Peer nodes
                        ForEach(Array(meshManager.connectedPeers.enumerated()), id: \.element.id) { index, peer in
                            let angle = (2 * .pi / Double(meshManager.connectedPeers.count)) * Double(index)
                            let peerX = centerX + radius * cos(angle)
                            let peerY = centerY + radius * sin(angle)

                            PeerNode(peer: peer)
                                .position(x: peerX, y: peerY)
                        }
                    }
                }
                .frame(height: 300)
            }
            .frame(height: 320)
        }
    }

    // MARK: - Peers List Section
    private var peersListSection: some View {
        VStack(spacing: 10) {
            Text("Connected Peers")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if meshManager.connectedPeers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No peers connected")
                        .foregroundColor(.secondary)
                    Text("Make sure other devices are nearby with the app open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
            } else {
                ForEach(meshManager.connectedPeers) { peer in
                    PeerRow(peer: peer)
                }
            }
        }
    }

    // MARK: - Test Controls
    private var testControlsSection: some View {
        VStack(spacing: 10) {
            Text("Test Controls")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                Button(action: {
                    meshManager.broadcastMessage(.ping)
                    showTestMessage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showTestMessage = false
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Send Ping to All Peers")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(meshManager.connectedPeers.isEmpty)

                if showTestMessage {
                    Text("Ping sent! ✓")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
        }
    }

    // MARK: - Messages Section
    private var messagesSection: some View {
        VStack(spacing: 10) {
            Text("Recent Messages")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if meshManager.receivedMessages.isEmpty {
                Text("No messages yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(16)
            } else {
                ForEach(Array(meshManager.receivedMessages.reversed().prefix(5).enumerated()), id: \.offset) { _, message in
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                        Text(message)
                            .font(.caption)
                        Spacer()
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Status Indicator Component
struct StatusIndicator: View {
    let icon: String
    let label: String
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isActive ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(isActive ? color : .secondary)
        }
    }
}

// MARK: - Peer Node Component
struct PeerNode: View {
    let peer: PeerInfo

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(peer.hasInternet ? Color.green : Color.gray)
                    .frame(width: 50, height: 50)
                    .shadow(color: peer.hasInternet ? .green.opacity(0.3) : .gray.opacity(0.3), radius: 8)

                Image(systemName: peer.hasInternet ? "iphone.radiowaves.left.and.right" : "iphone")
                    .font(.system(size: 20))
                    .foregroundColor(.white)

                // Internet indicator badge
                if peer.hasInternet {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "wifi")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        )
                        .offset(x: 18, y: -18)
                }
            }

            Text(String(peer.id.prefix(8)))
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .frame(width: 70)
    }
}

// MARK: - Peer Row Component
struct PeerRow: View {
    let peer: PeerInfo

    var body: some View {
        HStack {
            // Peer icon
            Image(systemName: peer.hasInternet ? "iphone.radiowaves.left.and.right" : "iphone")
                .font(.title2)
                .foregroundColor(peer.hasInternet ? .green : .blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(peer.id)
                    .font(.headline)

                HStack(spacing: 10) {
                    Label(
                        peer.hasInternet ? "Online" : "Offline",
                        systemImage: peer.hasInternet ? "wifi" : "wifi.slash"
                    )
                    .font(.caption)
                    .foregroundColor(peer.hasInternet ? .green : .secondary)

                    if peer.batteryLevel > 0 {
                        Label(
                            "\(Int(peer.batteryLevel * 100))%",
                            systemImage: batteryIcon(for: peer.batteryLevel)
                        )
                        .font(.caption)
                        .foregroundColor(batteryColor(for: peer.batteryLevel))
                    }
                }
            }

            Spacer()

            // Connection state
            Circle()
                .fill(peer.state == .connected ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func batteryIcon(for level: Float) -> String {
        switch level {
        case 0.75...1.0: return "battery.100"
        case 0.5..<0.75: return "battery.75"
        case 0.25..<0.5: return "battery.50"
        default: return "battery.25"
        }
    }

    private func batteryColor(for level: Float) -> Color {
        level < 0.25 ? .red : .secondary
    }
}

#Preview {
    MeshNetworkView()
}
