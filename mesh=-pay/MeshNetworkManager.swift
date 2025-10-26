import Foundation
import MultipeerConnectivity
import Combine
import Network

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
    @Published var offlineMode = false // When true, skip active internet checks for demos
    @Published var networkPathSummary: String = "Unknown"

    private var walletPublicKey: String = ""
    private var invitedPeers = Set<String>() // Track peers we've already invited
    private var discoveredPeers = Set<MCPeerID>() // Track all discovered peers for reconnection
    private var lastInvitationTime: [String: Date] = [:] // Cooldown for invitations

    // Network path monitoring
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "mesh.path.monitor")
    private var discoveryRestartWorkItem: DispatchWorkItem?

    // Relay functionality - reference to wallet manager for submitting transactions
    weak var walletManager: WalletManager?

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

        // Initialize session with:
        // - No encryption for better compatibility and performance
        // - This allows fallback to Bluetooth when WiFi is unavailable
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .none  // Better for Bluetooth fallback
        )

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

        // Start monitoring interface/path changes (Wi‑Fi/Bluetooth/Cellular)
        startMonitoringNetworkPath()
    }

    // MARK: - Start/Stop Mesh Network
    func startMesh() {
        guard !isAdvertising && !isBrowsing else {
            print("🌐 Mesh network already running")
            return
        }

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isAdvertising = true
        isBrowsing = true
        print("🌐 Mesh network started - Advertising and Browsing")

        // Start periodic connection cleanup (less frequent to reduce overhead)
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleConnections()
            }
        }

        // Only restart discovery occasionally (less disruptive)
        // Disabled for now as it causes disconnections
        // Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
        //     Task { @MainActor in
        //         self?.restartDiscovery()
        //     }
        // }
    }

    private func restartDiscovery() {
        print("🔄 Restarting discovery to handle network changes")

        // Stop and restart browsing/advertising to refresh Bluetooth/WiFi connections
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            print("🔄 Discovery restarted")
        }
    }

    // Public helper so UI can manually trigger a refresh
    func restartDiscoveryNow() {
        restartDiscovery()
    }

    private func scheduleDebouncedDiscoveryRestart() {
        discoveryRestartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restartDiscovery()
        }
        discoveryRestartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
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
        // Honor Offline Mode (useful for demos to avoid HEAD pings/log spam)
        if offlineMode {
            // Derive availability from NWPath status only
            // hasInternet is updated by path monitor; just broadcast if needed
            broadcastStatusIfChanged()
            return
        }

        // Simple check - try to reach a known endpoint
        guard let url = URL(string: "https://www.apple.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                // Consider connection available if we got a normal HTTP response
                let httpOk = (response as? HTTPURLResponse)?.statusCode
                let hasConnection = httpOk == 200 || httpOk == 301 || httpOk == 302
                self.hasInternet = hasConnection

                self.broadcastStatusIfChanged()
            }
        }.resume()
    }

    private func broadcastStatusIfChanged() {
        // Only broadcast if status changed significantly
        let batteryLevel = getBatteryLevel()
        let batteryChanged = abs(batteryLevel - lastBroadcastedBattery) > 0.1 // 10% change
        let internetChanged = hasInternet != lastBroadcastedInternetStatus

        if internetChanged || batteryChanged {
            lastBroadcastedInternetStatus = hasInternet
            lastBroadcastedBattery = batteryLevel

            let message = MeshMessage.peerInfo(hasInternet: hasInternet, batteryLevel: batteryLevel)
            broadcastMessage(message)
            print("📡 Broadcasting status: internet=\(hasInternet), battery=\(Int(batteryLevel*100))%")
        }
    }

    private func startMonitoringNetworkPath() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            Task { @MainActor in
                let satisfied = path.status == .satisfied
                self.hasInternet = satisfied

                var components: [String] = []
                if path.usesInterfaceType(.wifi) { components.append("Wi‑Fi") }
                if path.usesInterfaceType(.cellular) { components.append("Cellular") }
                if path.usesInterfaceType(.wiredEthernet) { components.append("Ethernet") }
                if path.usesInterfaceType(.other) { components.append("Other") }
                let transports = components.isEmpty ? "None" : components.joined(separator: ", ")
                self.networkPathSummary = satisfied ? "Online via: \(transports)" : "Offline (no route)"

                // Restart discovery when path changes to re‑negotiate transport (Bluetooth/AWDL/Wi‑Fi)
                self.scheduleDebouncedDiscoveryRestart()

                // Inform peers if status changed
                self.broadcastStatusIfChanged()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
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

                // Disabled automatic reconnection - causing connection storms
                // Let natural discovery handle reconnections
                // if discoveredPeers.contains(peerID) {
                //     print("🔄 Will attempt to reconnect to \(peerID.displayName) in 5 seconds")
                // }

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

            // If we have internet, relay the transaction to Stellar network
            if hasInternet, let walletManager = walletManager {
                Task {
                    await relayPaymentToNetwork(
                        recipient: recipient,
                        amount: amount,
                        txXDR: escrowTx
                    )
                }
            } else {
                // If we don't have internet, forward to other peers
                print("📡 No internet, forwarding payment request to other peers")
                broadcastMessage(message)
            }

        case .paymentConfirmation(let escrowId, let status):
            print("✅ Received payment confirmation: \(escrowId) - \(status)")
            receivedMessages.append("Confirmation: \(status)")

            // Update transaction status in wallet manager
            if let walletManager = walletManager {
                Task {
                    await MainActor.run {
                        // Find and update pending transaction
                        if let index = walletManager.transactions.firstIndex(where: {
                            $0.status == .pending
                        }) {
                            var updatedTx = walletManager.transactions[index]
                            // Create new transaction with updated status
                            let newTx = PaymentTransaction(
                                id: escrowId,
                                type: updatedTx.type,
                                amount: updatedTx.amount,
                                destination: updatedTx.destination,
                                timestamp: updatedTx.timestamp,
                                status: status == "confirmed" ? .confirmed : .failed
                            )
                            walletManager.transactions[index] = newTx
                            print("✅ Updated transaction status to \(status)")

                            // Refresh balance if confirmed
                            if status == "confirmed" {
                                Task {
                                    await walletManager.fetchBalance()
                                }
                            }
                        }
                    }
                }
            }

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

    // MARK: - Relay Logic
    private func relayPaymentToNetwork(recipient: String, amount: String, txXDR: String) async {
        guard let walletManager = walletManager,
              let amountDouble = Double(amount) else {
            print("❌ Cannot relay payment - invalid data")
            return
        }

        do {
            let txHash = try await walletManager.submitSignedTransaction(
                xdr: txXDR,
                destination: recipient,
                amount: amountDouble
            )

            print("✅ Relayed payment to network. TX Hash: \(txHash)")

            // Broadcast confirmation back through mesh
            let confirmation = MeshMessage.paymentConfirmation(
                escrowId: txHash,
                status: "confirmed"
            )
            broadcastMessage(confirmation)

            await MainActor.run {
                receivedMessages.append("Relayed payment ✓")
            }
        } catch {
            print("❌ Failed to relay payment: \(error.localizedDescription)")

            // Broadcast failure
            let confirmation = MeshMessage.paymentConfirmation(
                escrowId: UUID().uuidString,
                status: "failed"
            )
            broadcastMessage(confirmation)
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
        // Auto-invite found peers if not already connected/invited
        Task { @MainActor in
            // Track discovered peer
            self.discoveredPeers.insert(peerID)

            let isAlreadyConnected = self.session.connectedPeers.contains(peerID)
            let isConnecting = self.connectedPeers.contains { $0.peerID == peerID && $0.state == .connecting }
            let alreadyInvited = self.invitedPeers.contains(peerID.displayName)

            // Check invitation cooldown - wait at least 10 seconds between invitations
            let lastInvite = self.lastInvitationTime[peerID.displayName]
            let cooldownExpired = lastInvite == nil || Date().timeIntervalSince(lastInvite!) > 10.0

            if !isAlreadyConnected && !isConnecting && !alreadyInvited && cooldownExpired {
                print("🔍 Found peer: \(peerID.displayName) - sending invitation")
                self.invitedPeers.insert(peerID.displayName)
                self.lastInvitationTime[peerID.displayName] = Date()
                browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 20)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
        Task { @MainActor in
            self.invitedPeers.remove(peerID.displayName)
            self.discoveredPeers.remove(peerID)
        }
    }
}
