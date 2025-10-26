//
//  ContentView.swift
//  mesh=-pay
//
//  Created by Narasimha Teja Reddy on 10/25/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var walletManager = WalletManager()

    var body: some View {
        NavigationView {
            if walletManager.isWalletCreated {
                WalletView()
                    .environmentObject(walletManager)
            } else {
                WalletSetupView()
                    .environmentObject(walletManager)
            }
        }
    }
}

#Preview {
    ContentView()
}
