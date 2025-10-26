//
//  ContentView.swift
//  mesh=-pay
//
//  Created by Narasimha Teja Reddy on 10/25/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var walletManager = WalletManager()
    @StateObject private var meshManager: MeshNetworkManager
    @Environment(\.scenePhase) var scenePhase

    init() {
        let walletMgr = WalletManager()
        _walletManager = StateObject(wrappedValue: walletMgr)

        let meshMgr = MeshNetworkManager(walletPublicKey: walletMgr.publicKey)
        meshMgr.walletManager = walletMgr
        _meshManager = StateObject(wrappedValue: meshMgr)
    }

    var body: some View {
        NavigationView {
            if walletManager.isWalletCreated {
                WalletView()
                    .environmentObject(walletManager)
                    .environmentObject(meshManager)
            } else {
                WalletSetupView()
                    .environmentObject(walletManager)
                    .environmentObject(meshManager)
            }
        }
        .onAppear {
            // Start mesh network when wallet is created
            if walletManager.isWalletCreated && !meshManager.isAdvertising {
                meshManager.startMesh()
            }
        }
        .onChange(of: walletManager.isWalletCreated) { isCreated in
            if isCreated && !meshManager.isAdvertising {
                meshManager.startMesh()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // Keep mesh running even when app goes to background
            if newPhase == .active && walletManager.isWalletCreated && !meshManager.isAdvertising {
                meshManager.startMesh()
            }
            // Don't stop mesh when going to background - it can run in background
        }
    }
}

#Preview {
    ContentView()
}
