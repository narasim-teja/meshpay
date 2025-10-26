import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Mesh Message Types
enum MeshMessage: Codable {
    case paymentRequest(recipient: String, amount: String, escrowTx: String)
    case paymentConfirmation(escrowId: String, status: String)
    case peerInfo(hasInternet: Bool, batteryLevel: Float)
    case ping

    enum CodingKeys: String, CodingKey {
        case type, recipient, amount, escrowTx, escrowId, status, hasInternet, batteryLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "paymentRequest":
            let recipient = try container.decode(String.self, forKey: .recipient)
            let amount = try container.decode(String.self, forKey: .amount)
            let escrowTx = try container.decode(String.self, forKey: .escrowTx)
            self = .paymentRequest(recipient: recipient, amount: amount, escrowTx: escrowTx)
        case "paymentConfirmation":
            let escrowId = try container.decode(String.self, forKey: .escrowId)
            let status = try container.decode(String.self, forKey: .status)
            self = .paymentConfirmation(escrowId: escrowId, status: status)
        case "peerInfo":
            let hasInternet = try container.decode(Bool.self, forKey: .hasInternet)
            let batteryLevel = try container.decode(Float.self, forKey: .batteryLevel)
            self = .peerInfo(hasInternet: hasInternet, batteryLevel: batteryLevel)
        case "ping":
            self = .ping
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .paymentRequest(let recipient, let amount, let escrowTx):
            try container.encode("paymentRequest", forKey: .type)
            try container.encode(recipient, forKey: .recipient)
            try container.encode(amount, forKey: .amount)
            try container.encode(escrowTx, forKey: .escrowTx)
        case .paymentConfirmation(let escrowId, let status):
            try container.encode("paymentConfirmation", forKey: .type)
            try container.encode(escrowId, forKey: .escrowId)
            try container.encode(status, forKey: .status)
        case .peerInfo(let hasInternet, let batteryLevel):
            try container.encode("peerInfo", forKey: .type)
            try container.encode(hasInternet, forKey: .hasInternet)
            try container.encode(batteryLevel, forKey: .batteryLevel)
        case .ping:
            try container.encode("ping", forKey: .type)
        }
    }
}

// MARK: - Peer Information
struct PeerInfo: Identifiable {
    let id: String
    let peerID: MCPeerID
    var hasInternet: Bool
    var batteryLevel: Float
    var lastSeen: Date
    var state: MCSessionState
}

// MARK: - Mesh Network Manager
@MainActor
class MeshNetworkManager: NSObject, ObservableObject {
    private let serviceType = "stellarmesh"
    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    @Published var connectedPeers: [PeerInfo] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var receivedMessages: [String] = []
    @Published var hasInternet = true

    private var walletPublicKey: String = ""
    private var invitedPeers = Set<String>() // Track peers we've already invited

    init(walletPublicKey: String = "") {
        // Create unique peer ID using truncated wallet public key
        let displayName: String
        if !walletPublicKey.isEmpty {
            self.walletPublicKey = walletPublicKey
            // Use truncated format: first 6 + ... + last 4 characters
            let prefix = String(walletPublicKey.prefix(6))
            let suffix = String(walletPublicKey.suffix(4))
            displayName = "\(prefix)...\(suffix)"
        } else {
            // Fallback to device name if no wallet key provided
            displayName = UIDevice.current.name
        }
        self.myPeerID = MCPeerID(displayName: displayName)

        // Initialize session with optional encryption for better compatibility
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)

        // Initialize advertiser (makes this device discoverable)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)

        // Initialize browser (discovers other devices)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Start monitoring internet connectivity
        startMonitoringConnectivity()
    }

    // MARK: - Start/Stop Mesh Network
    func startMesh() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isAdvertising = true
        isBrowsing = true
        print("🌐 Mesh network started - Advertising and Browsing")

        // Start periodic connection cleanup (less frequent to reduce overhead)
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleConnections()
            }
        }
    }

    private func cleanupStaleConnections() {
        let actuallyConnected = session.connectedPeers
        connectedPeers = connectedPeers.filter { peer in
            actuallyConnected.contains(peer.peerID)
        }
    }

    func stopMesh() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isAdvertising = false
        isBrowsing = false
        connectedPeers.removeAll()
        print("🌐 Mesh network stopped")
    }

    // MARK: - Send Messages
    func sendMessage(_ message: MeshMessage, to peers: [MCPeerID]? = nil) {
        let targetPeers = peers ?? session.connectedPeers

        // Filter to only actually connected peers
        let connectedPeerIDs = session.connectedPeers
        let validTargetPeers = targetPeers.filter { connectedPeerIDs.contains($0) }

        guard !validTargetPeers.isEmpty else {
            print("⚠️ No peers connected to send message")
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            try session.send(data, toPeers: validTargetPeers, with: .reliable)
            print("📤 Sent message to \(validTargetPeers.count) peer(s)")
        } catch {
            print("❌ Error sending message: \(error.localizedDescription)")
            // If send fails, the peer might be disconnecting - clean up
            for peer in validTargetPeers {
                if session.connectedPeers.contains(peer) == false {
                    Task { @MainActor in
                        connectedPeers.removeAll { $0.peerID == peer }
                    }
                }
            }
        }
    }

    func broadcastMessage(_ message: MeshMessage) {
        sendMessage(message, to: session.connectedPeers)
    }

    // MARK: - Connectivity Monitoring
    private var lastBroadcastedInternetStatus: Bool = true
    private var lastBroadcastedBattery: Float = 1.0

    private func startMonitoringConnectivity() {
        // Check internet connectivity less frequently to avoid overwhelming the connection
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInternetConnectivity()
            }
        }
        // Do initial check
        Task { @MainActor in
            checkInternetConnectivity()
        }
    }

    private func checkInternetConnectivity() {
        // Simple check - try to reach a known endpoint
        guard let url = URL(string: "https://www.apple.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                // Consider connection available if we got any response (even non-200)
                // or if we're on cellular/wifi
                let hasConnection: Bool
                if let httpResponse = response as? HTTPURLResponse {
                    hasConnection = httpResponse.statusCode == 200 || httpResponse.statusCode == 301 || httpResponse.statusCode == 302
                } else {
                    // Fallback: assume online (since we can't definitively say we're offline)
                    hasConnection = true
                }
                self.hasInternet = hasConnection

                // Only broadcast if status changed significantly
                let batteryLevel = self.getBatteryLevel()
                let batteryChanged = abs(batteryLevel - self.lastBroadcastedBattery) > 0.1 // 10% change
                let internetChanged = hasConnection != self.lastBroadcastedInternetStatus

                if internetChanged || batteryChanged {
                    self.lastBroadcastedInternetStatus = hasConnection
                    self.lastBroadcastedBattery = batteryLevel

                    let message = MeshMessage.peerInfo(hasInternet: hasConnection, batteryLevel: batteryLevel)
                    self.broadcastMessage(message)
                    print("📡 Broadcasting status: internet=\(hasConnection), battery=\(Int(batteryLevel*100))%")
                }
            }
        }.resume()
    }

    // MARK: - Helper Methods
    private func getBatteryLevel() -> Float {
        let level = UIDevice.current.batteryLevel
        // batteryLevel returns -1.0 if battery monitoring is not enabled or not available
        return level >= 0 ? level : 1.0
    }

    func getPeerInfo(for peerID: MCPeerID) -> PeerInfo? {
        return connectedPeers.first { $0.peerID == peerID }
    }

    func getOnlinePeers() -> [PeerInfo] {
        return connectedPeers.filter { $0.hasInternet }
    }
}

// MARK: - MCSessionDelegate
extension MeshNetworkManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                print("✅ Connected to peer: \(peerID.displayName)")
                // Remove from invited list since connection succeeded
                invitedPeers.remove(peerID.displayName)

                // Add or update peer info - assume online until we get their status
                if let index = connectedPeers.firstIndex(where: { $0.peerID == peerID }) {
                    var updatedPeer = connectedPeers[index]
                    updatedPeer.state = state
                    connectedPeers[index] = updatedPeer
                } else {
                    let newPeer = PeerInfo(
                        id: peerID.displayName,
                        peerID: peerID,
                        hasInternet: true, // Assume online initially
                        batteryLevel: 1.0,
                        lastSeen: Date(),
                        state: state
                    )
                    connectedPeers.append(newPeer)
                }

                // Send our info to the new peer (just once on connection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    let message = MeshMessage.peerInfo(hasInternet: self.hasInternet, batteryLevel: self.getBatteryLevel())
                    self.sendMessage(message, to: [peerID])
                }

            case .connecting:
                print("🔄 Connecting to peer: \(peerID.displayName)")

            case .notConnected:
                print("❌ Disconnected from peer: \(peerID.displayName)")
                connectedPeers.removeAll { $0.peerID == peerID }
                // Allow re-invitation after disconnect
                invitedPeers.remove(peerID.displayName)

            @unknown default:
                print("⚠️ Unknown peer state")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let decoder = JSONDecoder()
                let message = try decoder.decode(MeshMessage.self, from: data)
                handleReceivedMessage(message, from: peerID)
            } catch {
                print("❌ Error decoding message: \(error)")
            }
        }
    }

    private func handleReceivedMessage(_ message: MeshMessage, from peerID: MCPeerID) {
        switch message {
        case .paymentRequest(let recipient, let amount, let escrowTx):
            print("💰 Received payment request: \(amount) to \(recipient)")
            receivedMessages.append("Payment: \(amount) to \(recipient.prefix(8))...")

        case .paymentConfirmation(let escrowId, let status):
            print("✅ Received payment confirmation: \(escrowId) - \(status)")
            receivedMessages.append("Confirmation: \(status)")

        case .peerInfo(let hasInternet, let batteryLevel):
            // Update peer info
            if let index = connectedPeers.firstIndex(where: { $0.peerID == peerID }) {
                connectedPeers[index].hasInternet = hasInternet
                connectedPeers[index].batteryLevel = batteryLevel
                connectedPeers[index].lastSeen = Date()
                print("📊 Updated \(peerID.displayName): internet=\(hasInternet), battery=\(Int(batteryLevel*100))%")
            }

        case .ping:
            print("🏓 Received ping from \(peerID.displayName)")
            receivedMessages.append("Ping from \(peerID.displayName)")
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for this implementation
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used for this implementation
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used for this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MeshNetworkManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📨 Received invitation from: \(peerID.displayName)")
        // Auto-accept invitations only if not already connected
        Task { @MainActor in
            let isAlreadyConnected = self.session.connectedPeers.contains(peerID)
            let isConnecting = self.connectedPeers.contains { $0.peerID == peerID && $0.state == .connecting }

            if !isAlreadyConnected && !isConnecting {
                invitationHandler(true, self.session)
            } else {
                print("⏭️  Skipping invitation - already connected/connecting to \(peerID.displayName)")
                invitationHandler(false, nil)
            }
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshNetworkManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")
        // Auto-invite found peers if not already connected/invited
        Task { @MainActor in
            let isAlreadyConnected = self.session.connectedPeers.contains(peerID)
            let isConnecting = self.connectedPeers.contains { $0.peerID == peerID && $0.state == .connecting }
            let alreadyInvited = self.invitedPeers.contains(peerID.displayName)

            if !isAlreadyConnected && !isConnecting && !alreadyInvited {
                self.invitedPeers.insert(peerID.displayName)
                browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 30)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        Task { @MainActor in
            self.invitedPeers.remove(peerID.displayName)
        }
    }
}
