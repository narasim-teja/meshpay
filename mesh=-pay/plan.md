# StellarMeshPay - Simplified Hackathon Plan

**Project:** Offline Stellar Payments via iOS Mesh Networking  
**Hackathon:** Stellar x EasyA  
**Track:** Open Innovation  
**Team Size:** 2-3 developers  
**Duration:** 8 days  

---

## 🎯 The Core Problem

**Problem:** People can't send cryptocurrency payments without internet connection.

**Real Scenarios:**
- Rural areas with spotty cellular coverage
- Natural disasters when cell towers are down
- International travelers avoiding roaming charges
- Remote markets where vendors have no data plans

---

## 💡 Our Solution

**Send Stellar payments offline by bouncing them through nearby phones via Bluetooth until someone with internet submits them to the blockchain.**

```
Alice (no internet) → Bob's phone (relay) → Carol's phone (has internet) → Stellar Network
```

**Key Innovation:** Smart contract escrow system that locks funds safely until recipient claims them, solving the "sequence number" problem that makes offline crypto payments impossible.

---

## 🏗️ System Architecture (Simplified)

```
┌─────────────────────┐    ┌─────────────────────┐
│   iOS Mobile App    │    │  Stellar Blockchain │
│                     │    │                     │
│ • Send/Receive UI   │───▶│ • Escrow Contract   │
│ • Mesh Networking   │    │ • Payment Claims    │
│ • Transaction Queue │    │ • Auto-refunds      │
└─────────────────────┘    └─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ MultipeerConnectivity│
│                     │
│ • Bluetooth LE     │
│ • WiFi Direct      │
│ • Message Routing  │
└─────────────────────┘
```

---

## 📱 5-Phase Development Plan

### Phase 1: Basic Wallet (Days 1-2) ✅ COMPLETE
**Goal:** Create secure Stellar wallet with simple UI

**Core Features:**
- ✅ Generate Stellar keypair
- ✅ Store private key in iOS Keychain
- ✅ Fund testnet account (Friendbot)
- ✅ Show balance and address
- ✅ Simple send/receive UI

**Deliverables:**
- ✅ Can create wallet
- ✅ Can send XLM online
- ✅ Transaction history works
- ✅ QR code for receiving

**Testing:** ✅ Send real payments on Stellar testnet

---

### Phase 3: Mesh Networking (Days 3-4) ✅ COMPLETE
**Goal:** Enable offline message routing between devices

**Status:** IMPLEMENTED FIRST (reordered from original plan)

**Core Features:**
- ✅ MultipeerConnectivity setup (Bluetooth + WiFi)
- ✅ Auto-discover nearby devices using wallet public keys
- ✅ Route messages through mesh network
- ✅ Handle peer connections/disconnections with cleanup
- ✅ Beautiful network visualization with animated nodes
- ✅ Battery level and internet status monitoring
- ✅ Duplicate connection prevention
- ✅ Privacy permissions configured

**Message Types:**
```swift
enum MeshMessage {
    case paymentRequest(recipient: String, amount: String, escrowTx: String)
    case paymentConfirmation(escrowId: String, status: String)
    case peerInfo(hasInternet: Bool, batteryLevel: Float)
    case ping
}
```

**Files Created:**
- `MeshNetworkManager.swift` - Core mesh networking logic
- `MeshNetworkView.swift` - Network visualization UI
- `mesh--pay-Info.plist` - Bluetooth/Network permissions

**Testing:** ✅ Peer discovery works, connections stable, pings routing successfully

---

### Phase 4: Offline Payment Flow (Days 5-6) 🔄 IN PROGRESS
**Goal:** Complete end-to-end offline payment experience

**Next Steps:**
1. **Detect sender's online/offline status** (use existing `hasInternet` from MeshNetworkManager)
2. **Modify SendPaymentView to support offline mode:**
   - If sender is offline: Create signed transaction and broadcast via mesh
   - If sender is online: Send normally via Stellar network
3. **Create transaction payload for mesh broadcast:**
   - Signed transaction XDR (base64 encoded)
   - Recipient address
   - Amount
   - Sender's public key
4. **Implement relay logic on online peers:**
   - Listen for `paymentRequest` messages
   - Submit transaction to Stellar Horizon
   - Broadcast confirmation back through mesh
5. **Queue system for offline transactions:**
   - Store pending transactions locally
   - Auto-retry when connection available
   - Show status in UI (pending/submitted/confirmed)

**Core Features TO DO:**
- [ ] Detect online/offline status in SendPaymentView
- [ ] Create signed transaction when offline
- [ ] Broadcast transaction via mesh to find internet connection
- [ ] Implement relay node logic (online devices submit for offline ones)
- [ ] Queue transactions locally with Core Data
- [ ] Auto-sync when back online
- [ ] Show pending/confirmed states in UI
- [ ] Handle edge cases (no peers, all peers offline, etc.)

**User Flow:**
1. Alice (offline) sends 100 XLM to Bob
2. App creates signed transaction locally
3. Broadcasts to nearby devices via Bluetooth
4. Carol's device (online) receives and submits to Stellar
5. Transaction confirmed on blockchain
6. Bob's app auto-detects incoming payment
7. Alice sees confirmation when back online

**Testing:** Full offline payment between 2 devices (1 offline, 1 relay, 1 recipient)

---

### Phase 2: Smart Contract Escrow (Days 7) 📋 PLANNED
**Goal:** Deploy escrow contract and integrate with app

**Status:** DEFERRED - Will implement after basic offline payments work

**Core Features:**
- Write Rust escrow contract (Soroban)
- Deploy to Stellar testnet
- Create escrow when sending offline
- Claim escrow when receiving
- Auto-refund after 24 hours

**Contract Functions:**
```rust
// Lock sender's funds in escrow
create_escrow(recipient: Address, amount: i128) -> u64

// Recipient claims the escrowed funds
claim_escrow(escrow_id: u64)

// Sender gets refund if unclaimed after 24h
refund_escrow(escrow_id: u64)
```

**Testing:** Create escrow → Claim → Verify funds moved

---

### Phase 5: Polish & Demo (Day 8) 📋 PLANNED
**Goal:** Production-ready app with impressive demo

**Polish Features:**
- Smooth animations and transitions
- Loading states and error handling
- Network status indicators
- Transaction history with status badges
- Face ID for payment authorization
- App icons and launch screen
- Haptic feedback

**Demo Preparation:**
- Two-device demo script
- Screen recording of full flow
- Stellar testnet explorer links
- Architecture diagrams
- GitHub repository with README

**Testing:** Full demo rehearsal, edge cases handled

---

## 🔐 The Sequence Number Solution

**The Problem:**
Stellar requires each transaction to have a unique, incrementing sequence number. When offline, you can't know what the next valid sequence number is.

**Our Solution:**
Instead of sending payments directly, we send money to an escrow contract first:

```
Traditional (fails offline):
Alice → (sequence 12346) → Bob directly ❌

Our approach (works offline):
Alice → (sequence 12346) → Escrow Contract ✅
Bob → (his own sequence) → Claim from Escrow ✅
```

This decouples sender and receiver sequences, making offline payments possible!

---

## 🛠️ Technology Stack

**iOS App:**
- Swift 6.0 + SwiftUI
- MultipeerConnectivity (mesh networking)
- Keychain Services (secure storage)
- Core Data (transaction history)

**Stellar Integration:**
- stellar-ios-mac-sdk
- Horizon API (testnet)
- Soroban smart contracts (Rust)

**Dependencies:**
```swift
// Package.swift
.package(url: "https://github.com/Soneso/stellar-ios-mac-sdk", from: "2.6.0")
.package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.0")
```

---

## 📊 Success Metrics

**For Demo:**
- ✅ Two phones can send payments offline
- ✅ Mesh routing works (A→B→C where C has internet)
- ✅ Escrow contract visible on Stellar Expert
- ✅ Recipient automatically receives payment
- ✅ UI looks professional and smooth

**For Judges:**
- ✅ Solves real problem clearly explained
- ✅ Technical innovation (mesh + escrow)
- ✅ Deep Stellar integration shown
- ✅ Actually works in live demo
- ✅ Production-ready code quality

---

## ⚠️ Potential Risks & Mitigation

**Risk 1: MultipeerConnectivity reliability**
- *Mitigation:* Test extensively on physical devices, have fallback demo video

**Risk 2: Smart contract complexity**
- *Mitigation:* Keep contract simple, focus on escrow basics only

**Risk 3: Time management**
- *Mitigation:* Each phase is independently valuable, can stop at Phase 3 and still have working demo

**Risk 4: iOS simulator limitations**
- *Mitigation:* Use physical devices from Day 1, borrow if needed

---

## 🎥 Demo Script (2 minutes)

**Setup:** 2 iPhones, 1 offline (airplane mode), 1 online

1. **"Here's the problem"** - Show offline phone can't send normal payment
2. **"Here's our solution"** - Send via mesh, show network visualization
3. **"The magic happens here"** - Online phone auto-submits to blockchain
4. **"And it's trustless"** - Show escrow contract on Stellar Expert
5. **"Recipient gets paid automatically"** - Show claim transaction
6. **"Sender gets confirmation"** - Turn airplane mode off, show confirmed

**Key Message:** "Offline crypto payments that actually work, secured by smart contracts."

---

## 💡 Why This Wins

**Innovation:** First working offline crypto payment system
**Technical Depth:** Real smart contracts, actual mesh networking
**Real Impact:** Solves genuine problem for billions without reliable internet
**Completeness:** Works end-to-end, not just a concept
**Stellar Integration:** Deep use of Horizon, Soroban, and Stellar features

---

## 📋 Daily Checkpoints

**End of Day 2:** Basic wallet works, can send XLM online
**End of Day 4:** Escrow contract deployed, can create/claim escrows
**End of Day 6:** Mesh networking works, messages route between devices
**End of Day 7:** Full offline payment flow complete
**End of Day 8:** Polished demo ready to submit

**Each checkpoint is a "go/no-go" decision point. If behind, simplify scope for remaining phases.**

---

## 🚀 Minimum Viable Demo

**If running short on time, the MVP is:**
- Phase 1: Basic wallet ✅
- Phase 2: Escrow contract ✅
- Phase 3: Simple mesh messaging ✅
- Manual demo: Send offline → Relay message → Manual submission

**This still demonstrates the core innovation and technical feasibility.**

---

## 📖 Key Takeaway

**The core insight:** Combine iOS mesh networking with Stellar smart contracts to solve the fundamental "sequence number problem" that makes offline crypto payments impossible.

**The innovation:** Pre-signed escrow transactions that decouple sender and receiver, enabling true offline payments with trustless security.

**The impact:** Unlocks cryptocurrency for billions without reliable internet access.

---

*This is a focused, achievable plan that demonstrates real innovation while being completeable in a hackathon timeframe. Build incrementally, test constantly, and you'll have a winning demo!* 🏆
