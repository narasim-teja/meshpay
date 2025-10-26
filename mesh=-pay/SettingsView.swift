//
//  SettingsView.swift
//  mesh=-pay
//
//  Settings and wallet management
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Wallet Info")) {
                    HStack {
                        Text("Network")
                        Spacer()
                        Text("Testnet")
                            .foregroundColor(.orange)
                    }

                    HStack {
                        Text("Balance")
                        Spacer()
                        Text("\(walletManager.balance) XLM")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Account")) {
                    Button(action: {
                        UIPasteboard.general.string = walletManager.publicKey
                    }) {
                        HStack {
                            Text("Copy Public Key")
                            Spacer()
                            Image(systemName: "doc.on.doc")
                        }
                    }

                    Link(destination: URL(string: "https://stellar.expert/explorer/testnet/account/\(walletManager.publicKey)")!) {
                        HStack {
                            Text("View on Explorer")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }

                Section(header: Text("Danger Zone")) {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Text("Delete Wallet")
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 5) {
                            Text("StellarMeshPay")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Phase 1: Basic Wallet")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Wallet?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    walletManager.deleteWallet()
                    dismiss()
                }
            } message: {
                Text("This will permanently delete your wallet and private key. This action cannot be undone.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(WalletManager())
}
