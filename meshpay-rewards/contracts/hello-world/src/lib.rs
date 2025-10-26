#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, token, Address, Env, String};

// Fee structure: 1% total
// - 0.5% to broadcaster (first relay peer)
// - 0.1% to relayer (submitter to blockchain)
// - 0.4% to protocol (contract deployer)
const TOTAL_FEE_BPS: u64 = 100;        // 1% in basis points (10000 = 100%)
const BROADCASTER_FEE_BPS: u64 = 50;   // 0.5%
const RELAYER_FEE_BPS: u64 = 10;       // 0.1%
const PROTOCOL_FEE_BPS: u64 = 40;      // 0.4%

#[contracttype]
#[derive(Clone)]
pub struct Payment {
    pub sender: Address,
    pub recipient: Address,
    pub broadcaster: Address,
    pub relayer: Address,
    pub amount: i128,
    pub claimed: bool,
}

#[contracttype]
pub enum DataKey {
    Payment(u64),      // payment_id -> Payment
    PaymentCount,      // total number of payments
    Protocol,          // protocol fee recipient (deployer)
}

#[contract]
pub struct MeshPayRewards;

#[contractimpl]
impl MeshPayRewards {
    /// Initialize the contract with protocol address (deployer)
    pub fn initialize(env: Env, protocol: Address) {
        if env.storage().instance().has(&DataKey::Protocol) {
            panic!("Already initialized");
        }
        env.storage().instance().set(&DataKey::Protocol, &protocol);
        env.storage().instance().set(&DataKey::PaymentCount, &0u64);
    }

    /// Create a new payment with broadcaster and relayer info
    /// Returns payment_id
    pub fn create_payment(
        env: Env,
        sender: Address,
        recipient: Address,
        broadcaster: Address,
        relayer: Address,
        amount: i128,
    ) -> u64 {
        // Verify sender authorization
        sender.require_auth();

        // Get next payment ID
        let payment_id: u64 = env
            .storage()
            .instance()
            .get(&DataKey::PaymentCount)
            .unwrap_or(0);

        // Calculate fees
        let total_fee = (amount * TOTAL_FEE_BPS as i128) / 10000;
        let net_amount = amount - total_fee;

        // Create payment record
        let payment = Payment {
            sender: sender.clone(),
            recipient: recipient.clone(),
            broadcaster: broadcaster.clone(),
            relayer: relayer.clone(),
            amount: net_amount,
            claimed: false,
        };

        // Store payment
        env.storage()
            .instance()
            .set(&DataKey::Payment(payment_id), &payment);

        // Increment payment count
        env.storage()
            .instance()
            .set(&DataKey::PaymentCount, &(payment_id + 1));

        payment_id
    }

    /// Distribute rewards to broadcaster, relayer, and protocol
    /// token_address: Address of the Stellar Asset Contract (use native XLM on testnet)
    /// from: Address that will pay the fees (typically the sender)
    pub fn distribute_rewards(
        env: Env,
        payment_id: u64,
        gross_amount: i128,
        token_address: Address,
        from: Address,
    ) {
        // Verify authorization from the payer
        from.require_auth();

        let payment: Payment = env
            .storage()
            .instance()
            .get(&DataKey::Payment(payment_id))
            .expect("Payment not found");

        // Calculate individual fees
        let broadcaster_fee = (gross_amount * BROADCASTER_FEE_BPS as i128) / 10000;
        let relayer_fee = (gross_amount * RELAYER_FEE_BPS as i128) / 10000;
        let protocol_fee = (gross_amount * PROTOCOL_FEE_BPS as i128) / 10000;

        // Get protocol address
        let protocol: Address = env
            .storage()
            .instance()
            .get(&DataKey::Protocol)
            .expect("Protocol address not set");

        // Initialize token client for transfers
        let token = token::Client::new(&env, &token_address);

        // Transfer fees to respective parties
        token.transfer(&from, &payment.broadcaster, &broadcaster_fee);
        token.transfer(&from, &payment.relayer, &relayer_fee);
        token.transfer(&from, &protocol, &protocol_fee);

        // Emit events for tracking
        env.events().publish(
            (String::from_str(&env, "reward_broadcaster"),),
            (payment.broadcaster, broadcaster_fee),
        );

        env.events().publish(
            (String::from_str(&env, "reward_relayer"),),
            (payment.relayer, relayer_fee),
        );

        env.events().publish(
            (String::from_str(&env, "reward_protocol"),),
            (protocol, protocol_fee),
        );
    }

    /// Get payment details
    pub fn get_payment(env: Env, payment_id: u64) -> Payment {
        env.storage()
            .instance()
            .get(&DataKey::Payment(payment_id))
            .expect("Payment not found")
    }

    /// Get total payment count
    pub fn get_payment_count(env: Env) -> u64 {
        env.storage()
            .instance()
            .get(&DataKey::PaymentCount)
            .unwrap_or(0)
    }

    /// Calculate fees for a given amount
    pub fn calculate_fees(env: Env, amount: i128) -> (i128, i128, i128, i128) {
        let broadcaster_fee = (amount * BROADCASTER_FEE_BPS as i128) / 10000;
        let relayer_fee = (amount * RELAYER_FEE_BPS as i128) / 10000;
        let protocol_fee = (amount * PROTOCOL_FEE_BPS as i128) / 10000;
        let net_amount = amount - broadcaster_fee - relayer_fee - protocol_fee;

        (net_amount, broadcaster_fee, relayer_fee, protocol_fee)
    }
}

mod test;
