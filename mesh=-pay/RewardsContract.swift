//
//  RewardsContract.swift
//  mesh=-pay
//
//  Handles Soroban smart contract integration for fee distribution
//

import Foundation

class RewardsContract {
    // Contract address from deployment
    static let contractAddress = "CACKTHTCAZW5EK5YCVEVLBIEN536TTBLMUQIJKLOICBDVBKANECMVZZC"

    // Native XLM token address on Stellar testnet
    // This is the Stellar Asset Contract (SAC) for native XLM
    static let nativeXLMAddress = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"

    // Protocol fee recipient (initialize parameter of the contract)
    static let protocolAddress = "GA6TY5O2JF2CDMY3LUFJEOV5IOQX5IALNQ5DRS4HU35VOPXNGDVZGG7R"

    // Fee structure (in basis points, 10000 = 100%)
    static let totalFeeBPS: Double = 100      // 1.0%
    static let broadcasterFeeBPS: Double = 50  // 0.5%
    static let relayerFeeBPS: Double = 10      // 0.1%
    static let protocolFeeBPS: Double = 40     // 0.4%

    /// Calculate fees for a given payment amount
    /// Returns: (netAmount, broadcasterFee, relayerFee, protocolFee)
    static func calculateFees(amount: Double) -> (net: Double, broadcaster: Double, relayer: Double, protocol: Double) {
        let broadcasterFee = (amount * broadcasterFeeBPS) / 10000
        let relayerFee = (amount * relayerFeeBPS) / 10000
        let protocolFee = (amount * protocolFeeBPS) / 10000
        let netAmount = amount - broadcasterFee - relayerFee - protocolFee

        return (netAmount, broadcasterFee, relayerFee, protocolFee)
    }

    /// Calculate gross amount needed to send a specific net amount
    /// (Reverse calculation: if recipient should get X, how much to charge sender)
    static func calculateGrossAmount(netAmount: Double) -> Double {
        // netAmount = grossAmount - (grossAmount * totalFeeBPS / 10000)
        // netAmount = grossAmount * (1 - totalFeeBPS/10000)
        // grossAmount = netAmount / (1 - totalFeeBPS/10000)
        return netAmount / (1 - (totalFeeBPS / 10000))
    }

    /// Format fee breakdown for display
    static func formatFeeBreakdown(amount: Double) -> String {
        let fees = calculateFees(amount: amount)
        return """
        Amount: \(String(format: "%.7f", amount)) XLM
        Network Fee (1%): \(String(format: "%.7f", fees.broadcaster + fees.relayer + fees.protocol)) XLM
          - Broadcaster: \(String(format: "%.7f", fees.broadcaster)) XLM
          - Relayer: \(String(format: "%.7f", fees.relayer)) XLM
          - Protocol: \(String(format: "%.7f", fees.protocol)) XLM
        Recipient receives: \(String(format: "%.7f", fees.net)) XLM
        """
    }
}

// MARK: - Payment with rewards info
struct RewardedPayment {
    let sender: String
    let recipient: String
    let broadcaster: String  // First peer who relayed from offline sender
    let relayer: String      // Online peer who submitted to blockchain
    let grossAmount: Double
    let netAmount: Double
    let broadcasterFee: Double
    let relayerFee: Double
    let protocolFee: Double
    let transactionXDR: String
}
