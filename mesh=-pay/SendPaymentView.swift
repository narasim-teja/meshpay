//
//  SendPaymentView.swift
//  mesh=-pay
//
//  Send payment interface with QR scanning
//

import SwiftUI

struct SendPaymentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss

    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var isSending = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Recipient")) {
                    HStack {
                        TextField("Stellar Address (G...)", text: $recipientAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        Button(action: {
                            // TODO: Add QR scanner
                        }) {
                            Image(systemName: "qrcode.viewfinder")
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
        }
    }
}

#Preview {
    SendPaymentView()
        .environmentObject(WalletManager())
}
