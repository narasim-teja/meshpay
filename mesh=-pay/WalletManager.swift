//
//  WalletManager.swift
//  mesh=-pay
//
//  Manages Stellar wallet operations including keypair generation,
//  secure storage, and blockchain interactions
//

import Foundation
import Security
import stellarsdk
import Combine
import LocalAuthentication

class WalletManager: ObservableObject {
    @Published var publicKey: String = ""
    @Published var balance: String = "0.00"
    @Published var isWalletCreated: Bool = false
    @Published var transactions: [PaymentTransaction] = []

    private let keychainService = "com.meshpay.stellar"
    private let keychainAccount = "stellar-private-key"
    private let sdk = StellarSDK(withHorizonUrl: "https://horizon-testnet.stellar.org")

    init() {
        loadWallet()
    }

    // MARK: - Wallet Creation

    func createWallet() {
        // Generate Stellar keypair
        let keypair = generateKeypair()

        // Save private key to Keychain
        guard savePrivateKey(keypair.privateKey) else {
            print("Failed to save private key to Keychain")
            return
        }

        self.publicKey = keypair.publicKey
        self.isWalletCreated = true

        // Fund account on testnet
        Task {
            await fundTestnetAccount()
        }
    }

    private func generateKeypair() -> (publicKey: String, privateKey: String) {
        do {
            let keyPair = try KeyPair.generateRandomKeyPair()
            return (keyPair.accountId, keyPair.secretSeed)
        } catch {
            print("Error generating keypair: \(error)")
            return ("", "")
        }
    }

    // MARK: - Keychain Operations

    private func savePrivateKey(_ privateKey: String) -> Bool {
        guard let data = privateKey.data(using: .utf8) else {
            return false
        }

        // Check if biometric authentication is available
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Create access control for biometric authentication
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny, // Requires Face ID/Touch ID
                nil
            ) else {
                // Fallback to standard security if biometrics not available
                return savePrivateKeyStandard(privateKey)
            }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: data,
                kSecAttrAccessControl as String: accessControl
            ]

            // Delete existing item if present
            SecItemDelete(query as CFDictionary)

            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        } else {
            // Biometrics not available, use standard storage
            return savePrivateKeyStandard(privateKey)
        }
    }
    
    private func savePrivateKeyStandard(_ privateKey: String) -> Bool {
        guard let data = privateKey.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item if present
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadPrivateKey(withBiometrics: Bool = false) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Require biometric authentication for payment operations
        if withBiometrics {
            let context = LAContext()
            context.localizedReason = "Authenticate to authorize payment"
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let privateKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return privateKey
    }

    private func loadWallet() {
        if let privateKey = loadPrivateKey() {
            do {
                // Derive public key from private key using Stellar SDK
                let keyPair = try KeyPair(secretSeed: privateKey)
                self.publicKey = keyPair.accountId
                self.isWalletCreated = true
                
                // Fetch current balance when wallet loads
                Task {
                    await fetchBalance()
                }
            } catch {
                print("Error loading keypair from private key: \(error)")
                // If we can't load the keypair, consider wallet not created
                isWalletCreated = false
            }
        }
    }

    // MARK: - Testnet Funding

    func fundTestnetAccount() async {
        guard !publicKey.isEmpty else { return }

        let friendbotURL = "https://friendbot.stellar.org?addr=\(publicKey)"

        guard let url = URL(string: friendbotURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("Account funded successfully")
                await fetchBalance()
            }
        } catch {
            print("Error funding account: \(error)")
        }
    }

    // MARK: - Balance & Transactions

    private func checkAccountExists(accountId: String) async -> Bool {
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AccountResponse, Error>) in
                sdk.accounts.getAccountDetails(accountId: accountId) { response in
                    switch response {
                    case .success(let details):
                        continuation.resume(returning: details)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    @unknown default:
                        continuation.resume(throwing: NSError(domain: "WalletManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown response"]))
                    }
                }
            }
            return true // Account exists
        } catch {
            return false // Account doesn't exist or error occurred
        }
    }

    func fetchBalance() async {
        guard !publicKey.isEmpty else { return }

        let horizonURL = "https://horizon-testnet.stellar.org/accounts/\(publicKey)"

        guard let url = URL(string: horizonURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let balances = json["balances"] as? [[String: Any]] {

                for balance in balances {
                    if let assetType = balance["asset_type"] as? String,
                       assetType == "native",
                       let amount = balance["balance"] as? String {

                        await MainActor.run {
                            self.balance = String(format: "%.2f", Double(amount) ?? 0.0)
                        }
                    }
                }
            }
        } catch {
            print("Error fetching balance: \(error)")
        }
    }


    func sendPayment(to destination: String, amount: Double) async -> Bool {
        guard let privateKey = loadPrivateKey(withBiometrics: true) else {
            print("Biometric authentication failed")
            return false
        }

        do {
            let sourceKeyPair = try KeyPair(secretSeed: privateKey)

            // Get account details
            let accountResponse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AccountResponse, Error>) in
                sdk.accounts.getAccountDetails(accountId: sourceKeyPair.accountId) { response in
                    switch response {
                    case .success(let details):
                        continuation.resume(returning: details)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    @unknown default:
                        continuation.resume(throwing: NSError(domain: "WalletManager", code: -1))
                    }
                }
            }

            // Check if destination exists
            let destinationExists = await checkAccountExists(accountId: destination)

            // Create operation
            let operation: stellarsdk.Operation
            if destinationExists {
                operation = try PaymentOperation(
                    sourceAccountId: sourceKeyPair.accountId,
                    destinationAccountId: destination,
                    asset: Asset(type: AssetType.ASSET_TYPE_NATIVE)!,
                    amount: Decimal(amount)
                )
            } else {
                operation = try CreateAccountOperation(
                    sourceAccountId: sourceKeyPair.accountId,
                    destinationAccountId: destination,
                    startBalance: Decimal(max(amount, 1.0))
                )
            }

            // Build and sign transaction
            let transaction = try stellarsdk.Transaction(
                sourceAccount: accountResponse,
                operations: [operation],
                memo: Memo.none
            )
            try transaction.sign(keyPair: sourceKeyPair, network: Network.testnet)

            // Submit transaction
            let txHash = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                sdk.transactions.submitTransaction(transaction: transaction) { response in
                    switch response {
                    case .success(let submitResponse):
                        continuation.resume(returning: submitResponse.transactionHash)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .destinationRequiresMemo:
                        continuation.resume(throwing: NSError(domain: "WalletManager", code: -1))
                    @unknown default:
                        continuation.resume(throwing: NSError(domain: "WalletManager", code: -1))
                    }
                }
            }

            // Add to history
            let newTransaction = PaymentTransaction(
                id: txHash,
                type: .sent,
                amount: amount,
                destination: destination,
                timestamp: Date(),
                status: .confirmed
            )

            await MainActor.run {
                transactions.insert(newTransaction, at: 0)
            }

            await fetchBalance()
            return true

        } catch {
            print("Error sending payment: \(error)")

            let failedTransaction = PaymentTransaction(
                id: UUID().uuidString,
                type: .sent,
                amount: amount,
                destination: destination,
                timestamp: Date(),
                status: .failed
            )

            await MainActor.run {
                transactions.insert(failedTransaction, at: 0)
            }

            return false
        }
    }

    func deleteWallet() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)

        publicKey = ""
        balance = "0.00"
        isWalletCreated = false
        transactions = []
    }
}

// MARK: - Models

struct PaymentTransaction: Identifiable {
    let id: String
    let type: TransactionType
    let amount: Double
    let destination: String
    let timestamp: Date
    let status: TransactionStatus
}

enum TransactionType {
    case sent
    case received
}

enum TransactionStatus {
    case pending
    case confirmed
    case failed
}
