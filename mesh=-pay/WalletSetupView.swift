//
//  WalletSetupView.swift
//  mesh=-pay
//
//  Initial wallet creation screen
//

import SwiftUI

struct WalletSetupView: View {
    @EnvironmentObject var walletManager: WalletManager

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("StellarMeshPay")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Offline Stellar Payments via Mesh Networking")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: {
                walletManager.createWallet()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create New Wallet")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Text("Your keys are stored securely in iOS Keychain")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .padding()
    }
}

#Preview {
    WalletSetupView()
        .environmentObject(WalletManager())
}
