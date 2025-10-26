//
//  WalletView.swift
//  mesh=-pay
//
//  Main wallet interface showing balance, transactions, and actions
//

import SwiftUI

struct WalletView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var showingSendSheet = false
    @State private var showingReceiveSheet = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance Card
                BalanceCard()

                // Action Buttons
                HStack(spacing: 15) {
                    ActionButton(icon: "arrow.up.circle.fill", title: "Send", color: .blue) {
                        showingSendSheet = true
                    }

                    ActionButton(icon: "arrow.down.circle.fill", title: "Receive", color: .green) {
                        showingReceiveSheet = true
                    }

                    ActionButton(icon: "arrow.clockwise.circle.fill", title: "Refresh", color: .orange) {
                        Task {
                            await walletManager.fetchBalance()
                        }
                    }
                }
                .padding(.horizontal)

                // Transaction History
                TransactionHistoryView()
            }
            .padding(.top)
        }
        .navigationTitle("Wallet")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $showingSendSheet) {
            SendPaymentView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $showingReceiveSheet) {
            ReceivePaymentView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(walletManager)
        }
        .task {
            await walletManager.fetchBalance()
        }
    }
}

struct BalanceCard: View {
    @EnvironmentObject var walletManager: WalletManager

    var body: some View {
        VStack(spacing: 10) {
            Text("Balance")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("\(walletManager.balance) XLM")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text(walletManager.publicKey.prefix(10) + "..." + walletManager.publicKey.suffix(6))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
    }
}

struct TransactionHistoryView: View {
    @EnvironmentObject var walletManager: WalletManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.horizontal)

            if walletManager.transactions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No transactions yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(walletManager.transactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: PaymentTransaction

    var body: some View {
        HStack {
            Image(systemName: transaction.type == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(transaction.type == .sent ? .red : .green)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.type == .sent ? "Sent" : "Received")
                    .font(.headline)
                Text(transaction.destination.prefix(10) + "...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(transaction.type == .sent ? "-" : "+")\(String(format: "%.2f", transaction.amount)) XLM")
                    .font(.headline)
                    .foregroundColor(transaction.type == .sent ? .red : .green)

                StatusBadge(status: transaction.status)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct StatusBadge: View {
    let status: TransactionStatus

    var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .green
        case .failed: return .red
        }
    }

    var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }

    var body: some View {
        Text(statusText)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }
}

#Preview {
    NavigationView {
        WalletView()
            .environmentObject(WalletManager())
    }
}
