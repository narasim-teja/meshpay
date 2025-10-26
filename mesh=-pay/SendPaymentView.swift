//
//  SendPaymentView.swift
//  mesh=-pay
//
//  Send payment interface with QR scanning
//

import SwiftUI

struct SendPaymentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var meshManager: MeshNetworkManager
    @Environment(\.dismiss) var dismiss

    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showQRScanner = false

    var body: some View {
        NavigationView {
            Form {
                // Online/Offline Status
                Section {
                    HStack {
                        Circle()
                            .fill(meshManager.hasInternet ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(meshManager.hasInternet ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !meshManager.hasInternet {
                            Text("\(meshManager.connectedPeers.count) peers")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Recipient")) {
                    HStack {
                        TextField("Stellar Address (G...)", text: $recipientAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        Button(action: {
                            showQRScanner = true
                        }) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                        }
                    }
                }

                Section(header: Text("Amount")) {
                    HStack {
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)

                        Text("XLM")
                            .foregroundColor(.secondary)
                    }

                    if let amountValue = Double(amount), amountValue > 0 {
                        Text("Available: \(walletManager.balance) XLM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: sendPayment) {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Send Payment")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValidInput || isSending)
                }
            }
            .navigationTitle("Send XLM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerView(scannedAddress: $recipientAddress)
            }
        }
    }

    var isValidInput: Bool {
        guard !recipientAddress.isEmpty,
              recipientAddress.hasPrefix("G"),
              let amountValue = Double(amount),
              amountValue > 0,
              let balanceValue = Double(walletManager.balance),
              amountValue <= balanceValue else {
            return false
        }
        return true
    }

    func sendPayment() {
        guard let amountValue = Double(amount) else { return }

        isSending = true

        Task {
            if meshManager.hasInternet {
                // Online: Send directly via Stellar network
                let success = await walletManager.sendPayment(to: recipientAddress, amount: amountValue)

                await MainActor.run {
                    isSending = false

                    if success {
                        dismiss()
                    } else {
                        errorMessage = "Failed to send payment"
                        showError = true
                    }
                }
            } else {
                // Offline: Create signed transaction and broadcast via mesh
                await sendOfflinePayment(to: recipientAddress, amount: amountValue)
            }
        }
    }

    func sendOfflinePayment(to recipient: String, amount: Double) async {
        do {
            print("📴 Creating offline payment transaction")
            // Create and sign transaction
            let signedTxXDR = try await walletManager.createSignedTransaction(to: recipient, amount: amount)
            print("✅ Transaction signed: \(signedTxXDR.prefix(50))...")

            // Broadcast via mesh network
            let paymentRequest = MeshMessage.paymentRequest(
                recipient: recipient,
                amount: String(amount),
                escrowTx: signedTxXDR
            )

            await MainActor.run {
                meshManager.broadcastMessage(paymentRequest)

                // Add to pending transactions
                let pendingTx = PaymentTransaction(
                    id: UUID().uuidString,
                    type: .sent,
                    amount: amount,
                    destination: recipient,
                    timestamp: Date(),
                    status: .pending
                )
                walletManager.transactions.insert(pendingTx, at: 0)

                isSending = false
                dismiss()
            }

            print("📡 Broadcasted offline payment via mesh network")
        } catch {
            await MainActor.run {
                isSending = false
                errorMessage = "Failed to create offline payment: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

#Preview {
    SendPaymentView()
        .environmentObject(WalletManager())
}
