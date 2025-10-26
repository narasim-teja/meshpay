#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, token, Address, Env, String};

// Fee structure: 1% total
const TOTAL_FEE_BPS: i128 = 100;     // 1.0% of gross
const BROADCASTER_FEE_BPS: i128 = 50; // 0.5%
const RELAYER_FEE_BPS: i128 = 10;     // 0.1%
const PROTOCOL_FEE_BPS: i128 = 40;    // 0.4%

#[contracttype]
#[derive(Clone)]
pub struct Payment {
    pub sender: Address,
    pub recipient: Address,
    pub broadcaster: Address,
    pub relayer: Address,
    pub gross_amount: i128, // in stroops (i128 per Soroban)
    pub net_amount: i128,   // gross - fees
    pub broadcaster_fee: i128,
    pub relayer_fee: i128,
    pub protocol_fee: i128,
}

#[contracttype]
pub enum DataKey {
    Payment(u64),
    PaymentCount,
    Protocol,
}

#[contract]
pub struct MeshPayRewards;

#[contractimpl]
impl MeshPayRewards {
    // One-time init with protocol fee recipient
    pub fn initialize(env: Env, protocol: Address) {
        if env.storage().instance().has(&DataKey::Protocol) {
            panic!("Already initialized");
        }
        env.storage().instance().set(&DataKey::Protocol, &protocol);
        env.storage().instance().set(&DataKey::PaymentCount, &0u64);
    }

    // View: compute fee split for a given gross amount
    pub fn calculate_fees(env: Env, gross_amount: i128) -> (i128, i128, i128, i128) {
        let broadcaster_fee = (gross_amount * BROADCASTER_FEE_BPS) / 10000;
        let relayer_fee = (gross_amount * RELAYER_FEE_BPS) / 10000;
        let protocol_fee = (gross_amount * PROTOCOL_FEE_BPS) / 10000;
        let net_amount = gross_amount - broadcaster_fee - relayer_fee - protocol_fee;
        (net_amount, broadcaster_fee, relayer_fee, protocol_fee)
    }

    // Record and distribute rewards — pays from RELAYER, no sender auth needed.
    // This is demo-friendly: the online device funds rewards; the main payment still happens via Horizon normally.
    // token_address: SAC address for native XLM (or other asset)
    pub fn record_and_distribute_rewards(
        env: Env,
        sender: Address,
        recipient: Address,
        broadcaster: Address,
        relayer: Address,
        gross_amount: i128,
        token_address: Address,
    ) -> u64 {
        // Ensure the relayer authorized this call (they will pay rewards)
        relayer.require_auth();

        // Load protocol address
        let protocol: Address = env
            .storage()
            .instance()
            .get(&DataKey::Protocol)
            .expect("Protocol not set");

        // Compute fees
        let (net_amount, broadcaster_fee, relayer_fee, protocol_fee) =
            Self::calculate_fees(env.clone(), gross_amount);

        // Persist payment record
        let payment_id: u64 = env
            .storage()
            .instance()
            .get(&DataKey::PaymentCount)
            .unwrap_or(0);

        let payment = Payment {
            sender: sender.clone(),
            recipient: recipient.clone(),
            broadcaster: broadcaster.clone(),
            relayer: relayer.clone(),
            gross_amount,
            net_amount,
            broadcaster_fee,
            relayer_fee,
            protocol_fee,
        };

        env.storage()
            .instance()
            .set(&DataKey::Payment(payment_id), &payment);

        env.storage()
            .instance()
            .set(&DataKey::PaymentCount, &(payment_id + 1));

        // Transfer rewards from relayer -> broadcaster/protocol via SAC
        let token = token::Client::new(&env, &token_address);
        if broadcaster_fee > 0 {
            token.transfer(&relayer, &broadcaster, &broadcaster_fee);
        }
        if protocol_fee > 0 {
            token.transfer(&relayer, &protocol, &protocol_fee);
        }
        // The relayer’s “own fee” is effectively retained — no transfer needed.

        // Emit events for indexing
        env.events().publish(
            (String::from_str(&env, "rewards_distributed"),),
            (
                payment_id,
                sender,
                recipient,
                broadcaster,
                relayer,
                gross_amount,
                net_amount,
                broadcaster_fee,
                relayer_fee,
                protocol_fee,
            ),
        );

        payment_id
    }

    // Views
    pub fn get_payment(env: Env, payment_id: u64) -> Payment {
        env.storage()
            .instance()
            .get(&DataKey::Payment(payment_id))
            .expect("Payment not found")
    }

    pub fn get_payment_count(env: Env) -> u64 {
        env.storage()
            .instance()
            .get(&DataKey::PaymentCount)
            .unwrap_or(0)
    }
}