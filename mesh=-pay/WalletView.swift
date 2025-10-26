//
//  WalletView.swift
//  mesh=-pay
//
//  Main wallet interface showing balance, transactions, and actions
//

import SwiftUI

struct WalletView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var meshManager: MeshNetworkManager
    @State private var showingSendSheet = false
    @State private var showingReceiveSheet = false
    @State private var showingSettings = false
    @State private var showingMeshNetwork = false
    @State private var toastMessage: String? = nil
    @State private var toastColor: Color = .green

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

                    ActionButton(icon: "arrow.clockwise.circle.fill", title: meshManager.isRefreshingBalance ? "Refreshing..." : "Refresh", color: .orange) {
                        Task {
                            if meshManager.hasInternet && !meshManager.offlineMode {
                                await walletManager.fetchBalance()
                                await MainActor.run {
                                    withAnimation {
                                        toastColor = .green
                                        toastMessage = "Refreshed online ✓"
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { toastMessage = nil }
                                    }
                                }
                            } else {
                                meshManager.requestBalanceFor(accountId: walletManager.publicKey)
                                await MainActor.run {
                                    withAnimation {
                                        toastColor = .blue
                                        toastMessage = "Refreshed via mesh ✓"
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { toastMessage = nil }
                                    }
                                }
                            }
                        }
                    }
                    .disabled(meshManager.isRefreshingBalance)
                }
                .padding(.horizontal)

                // Mesh Network Button
                Button(action: { showingMeshNetwork = true }) {
                    HStack {
                        Image(systemName: "wifi.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mesh Network")
                                .font(.headline)
                            Text("Connect with nearby devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .foregroundColor(.primary)
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
                .environmentObject(meshManager)
        }
        .sheet(isPresented: $showingReceiveSheet) {
            ReceivePaymentView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(walletManager)
        }
        .sheet(isPresented: $showingMeshNetwork) {
            MeshNetworkView()
                .environmentObject(walletManager)
                .environmentObject(meshManager)
        }
        .task {
            await walletManager.fetchBalance()
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                ToastBanner(message: message, color: toastColor)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
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

struct ToastBanner: View {
    let message: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(color)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationView {
        WalletView()
            .environmentObject(WalletManager())
    }
}
