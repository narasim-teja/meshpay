# mesh-pay (Offline Stellar Payments over Mesh)

## 🎯 The Core Problem

**Problem:** People can't send cryptocurrency payments without internet connection.

**Real Scenarios:**
- Rural areas with spotty cellular coverage
- Natural disasters when cell towers are down
- International travelers avoiding roaming charges
- Remote markets where vendors have no data plans

---

## 💡 Our Solution

**Send Stellar payments offline by bouncing them through nearby phones via Bluetooth/Wi‑Fi (AWDL) until someone with internet submits them to the blockchain.**

---

## 🚀 How It Works

1) Sender (offline or online)
- Creates and signs a Stellar transaction locally (no internet required)
- Broadcasts the signed XDR to nearby phones using Apple's MultipeerConnectivity (Bluetooth/Wi‑Fi/AWDL)

2) Mesh network
- Nearby peers discover each other and forward messages
- We deduplicate each payment by its XDR and add jittered debounce to prevent storms

3) Relay (any online peer)
- First online device submits the exact signed XDR to Horizon (unchanged)
- On success, it broadcasts a payment confirmation back through the mesh
- For the demo, it also distributes rewards (see Rewards) using on‑chain classic payments

4) Receiver and Sender update
- Receiver’s funds settle on Stellar as a normal on‑chain payment
- Offline devices request balance via mesh from any online peer and update their UI when the reply arrives

---

## 📡 Mesh + Connectivity Architecture

- MultipeerConnectivity (MCSession) for device‑to‑device transport
- NWPathMonitor to detect transport changes and restart discovery when needed
- Debounced discovery restart to avoid flapping
- Per‑transaction dedupe (by escrow XDR) + 3s + random jitter before relays
- Optional Offline Mode toggle to suppress internet probes for demos

---

## 🔁 Offline Balance Sync

- `balanceRequest(accountId)` sent to peers when you tap Refresh while offline
- Any online peer replies with `balanceUpdate(accountId, balance, sequence)`
- UI shows a small toast and a loading state until the response arrives (auto‑times out)

---

## 🏆 Network Incentive

Fee split (1% of gross):
- 0.5% Broadcaster (first hop)
- 0.1% Relayer (online submitter)
- 0.4% Protocol

Current implementation:
- Rewards are sent from the relayer’s wallet immediately after relay:
  - Broadcaster receives 0.5% (skipped if same as relayer)
  - Protocol receives 0.4% at `GA6TY5O2JF2CDMY3LUFJEOV5IOQX5IALNQ5DRS4HU35VOPXNGDVZGG7R`
  - Relayer keeps 0.1%

Smart contract:
- Contract: `CACKTHTCAZW5EK5YCVEVLBIEN536TTBLMUQIJKLOICBDVBKANECMVZZC`
- Native XLM SAC: `CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC`
- Method: `record_and_distribute_rewards(sender, recipient, broadcaster, relayer, gross_amount, token_address)`
- App scaffolding exists (`SorobanHelper`) and can be switched on when Soroban RPC simulate/sign/send 

---

## 🔒 Security Model

- On‑chain double‑spend protection via Stellar sequence numbers
- Relay cannot modify payments: any change invalidates the sender’s signature
- Mesh replay mitigations: per‑XDR dedupe, TTL, debounce, and no infinite rebroadcast
- Future hardening: signed mesh payloads, short timebounds on offline txs, fee‑bump/sponsorship support

---

## 🛠️ Build & Run

1) Open `mesh=-pay.xcodeproj` in Xcode 15+
2) Run on two or more iPhones (grant Bluetooth/Local Network permissions)
3) In the app:
   - Create/fund wallets (testnet) and open Mesh Network screen
   - Toggle Offline Mode for demo if needed
   - Try sending from one phone while it’s offline; keep another phone online as relay

Permissions to allow on first run: Bluetooth, Local Network, Camera (for QR scan)

---

## ⚙️ Configuration

- Rewards: `RewardsContract.swift`
  - `contractAddress` (Soroban)
  - `nativeXLMAddress` (SAC)
  - `protocolAddress` (protocol recipient)
- Mesh debug: `MeshNetworkView.swift`
  - Offline Mode toggle
  - Restart Discovery button
  - Path summary (Wi‑Fi/Cellular)
