//
//  SorobanHelper.swift
//  mesh=-pay
//
//  Helper for Soroban smart contract interactions
//

import Foundation
import stellarsdk

class SorobanHelper {
    private let sdk = StellarSDK(withHorizonUrl: "https://horizon-testnet.stellar.org")


    func distributeRewards(
        from sourceKeyPair: KeyPair,
        paymentId: UInt64,
        sender: String,
        recipient: String,
        broadcaster: String,
        relayer: String,
        grossAmount: Double
    ) async throws -> String {

        // Convert amount to i128 (Soroban uses i128 for amounts in stroops)
        let amountInStroops = Int64(grossAmount * 10_000_000)

        // Contract and token addresses
        let contractId = RewardsContract.contractAddress
        let tokenAddress = RewardsContract.nativeXLMAddress

        print("🔧 Building Soroban transaction:")
        print("   Contract: \(contractId)")
        print("   Function: record_and_distribute_rewards")
        print("   Payment ID: \(paymentId)")
        print("   Amount: \(grossAmount) XLM")

        
        return try await invokeContractViaHorizon(
            contractId: contractId,
            functionName: "record_and_distribute_rewards",
            args: [
                "sender": sender,
                "recipient": recipient,
                "broadcaster": broadcaster,
                "relayer": relayer,
                "grossAmount": amountInStroops,
                "tokenAddress": tokenAddress
            ],
            sourceKeyPair: sourceKeyPair
        )
    }

    /// Manual contract invocation via Horizon API
    private func invokeContractViaHorizon(
        contractId: String,
        functionName: String,
        args: [String: Any],
        sourceKeyPair: KeyPair
    ) async throws -> String {

        // Stellar's Soroban RPC endpoint (testnet)
        let sorobanRpcUrl = "https://soroban-testnet.stellar.org"

        print("📡 Invoking contract via Soroban RPC...")
        print("   Endpoint: \(sorobanRpcUrl)")
        print("   Contract: \(contractId)")
        print("   Function: \(functionName)")



        // Return placeholder hash
        return "SOROBAN_TX_\(UUID().uuidString.prefix(16))"
    }

    /// Distribute collected fees to broadcaster, relayer, and protocol
    /// Called by the relayer after successfully submitting a payment
    func distributeFees(
        from relayerPublicKey: String,
        broadcaster: String,
        relayer: String,
        grossAmount: Double
    ) async throws -> String {
        let fees = RewardsContract.calculateFees(amount: grossAmount)
        print("💸 Distributing fees (placeholder) ...")
        print("   Broadcaster: \(broadcaster)")
        print("   Relayer: \(relayer)")
        print("   Gross: \(String(format: "%.4f", grossAmount)) XLM")
        print("   Earned -> Broadcaster: \(String(format: "%.4f", fees.broadcaster)) XLM, Relayer: \(String(format: "%.4f", fees.relayer)) XLM, Protocol: \(String(format: "%.4f", fees.protocol)) XLM")
        return "FEE_DIST_\(UUID().uuidString.prefix(16))"
    }
}
