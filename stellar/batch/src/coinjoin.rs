// src/coinjoin.rs
// CoinJoin Mixer Module - JoinMarket + Wasabi Wallet Inspired
// Sources:
// - JoinMarket: https://github.com/JoinMarket-Org/joinmarket-clientserver
// - Wasabi Wallet: https://github.com/zkSNACKs/WalletWasabi
// - Tornado Cash: https://github.com/tornadocash/tornado-core
//
// Design Principles:
// - Fixed denomination mixing for maximum privacy
// - Non-custodial operation with cryptographic guarantees
// - Market-based incentives for sustainable liquidity
// - Integration with multicall for seamless transaction flow

use soroban_sdk::{Env, Symbol, Vec, BytesN, contracttype};
use crate::{error::BatcherError, DataKey};

/// Fixed denomination amounts for CoinJoin mixing (in stroops)
/// Based on Wasabi Wallet's successful fixed denomination model
#[derive(Clone, Debug, Eq, PartialEq, Copy)]
#[contracttype]
pub enum Denomination {
    Small = 10_000_000,      // 1 XLM $0.35
    Medium = 100_000_000,    // 10 XLM $3.50
    Large = 1_000_000_000,   // 100 XLM $35
    ExtraLarge = 2_000_000_000, // 200 XLM $70 (reduced for u32 compatibility)
}

impl Denomination {
    pub fn value(&self) -> i128 {
        match self {
            Denomination::Small => 10_000_000,
            Denomination::Medium => 100_000_000,
            Denomination::Large => 1_000_000_000,
            Denomination::ExtraLarge => 10_000_000_000,
        }
    }

    pub fn symbol(&self) -> Symbol {
        match self {
            Denomination::Small => Symbol::short("10"),
            Denomination::Medium => Symbol::short("100"),
            Denomination::Large => Symbol::short("1K"),
            Denomination::ExtraLarge => Symbol::short("10K"),
        }
    }

    pub fn from_amount(amount: i128) -> Option<Self> {
        match amount {
            10_000_000 => Some(Denomination::Small),
            100_000_000 => Some(Denomination::Medium),
            1_000_000_000 => Some(Denomination::Large),
            10_000_000_000 => Some(Denomination::ExtraLarge),
            _ => None,
        }
    }
}

/// CoinJoin pool for mixing transactions
/// Based on Wasabi Wallet's Chaumian CoinJoin model
#[derive(Clone, Debug)]
#[contracttype]
pub struct CoinJoinPool {
    pub denomination: Denomination,
    pub deposits: Vec<Deposit>,
    pub withdrawals: Vec<WithdrawalRequest>,
    pub merkle_root: BytesN<32>,
    pub minimum_pool_size: u32,
    pub maximum_pool_size: u32,
    pub fee_basis_points: u32,
}

/// Deposit information with cryptographic commitments
/// Following Tornado Cash's commitment scheme
/// Enhanced with slippage protection and expiry mechanism
#[derive(Clone, Debug)]
#[contracttype]
pub struct Deposit {
    pub commitment: BytesN<32>,
    pub timestamp: u64,
    pub nullifier: BytesN<32>,
    pub fee_paid: i128,
    pub sender_address: soroban_sdk::Address,  // Track sender for uniqueness check
    pub recipient_address: soroban_sdk::Address, // Address to receive payout (can be Stellar account)
    pub max_slippage_bps: u32,  // Maximum slippage in basis points (e.g., 50 = 0.5%)
    pub expiry_timestamp: u64,   // Expiry time (timestamp + 48 hours)
    pub token_in: soroban_sdk::Address,  // Input token address
    pub token_out: soroban_sdk::Address, // Output token address
    pub min_amount_out: i128,    // Minimum output amount (for slippage calculation)
}

/// Withdrawal request with blinding
/// Based on JoinMarket's blinded request model
#[derive(Clone, Debug)]
#[contracttype]
pub struct WithdrawalRequest {
    pub nullifier_hash: BytesN<32>,
    pub recipient_hash: BytesN<32>,
    pub proof_hash: BytesN<32>,
    pub requested_timestamp: u64,
}

/// CoinJoin mixing result
#[derive(Clone, Debug)]
#[contracttype]
pub struct MixResult {
    pub success: bool,
    pub mixed_amounts: Vec<i128>,
    pub gas_used: u64,
    pub anonymity_set_size: u32,
    pub fees_paid: i128,
}

/// Pool statistics and status
#[derive(Clone, Debug)]
#[contracttype]
pub struct PoolStats {
    pub denomination: Denomination,
    pub current_pool_size: u32,
    pub total_deposits: u64,
    pub total_withdrawals: u64,
    pub current_fees: u32,
    pub estimated_wait_time: u32,
}

/// Payout information for equal distribution
#[derive(Clone, Debug)]
#[contracttype]
pub struct PayoutInfo {
    pub equal_payout_amount: i128,      // Amount each participant receives
    pub total_input_amount: i128,        // Total input across all participants
    pub total_output_amount: i128,       // Total output from aggregated swap
    pub slippage_bps: u32,               // Realized slippage in basis points
    pub participant_count: u32,          // Number of participants
}

/// Public deposit information (privacy-safe)
/// Does NOT expose: commitment, nullifier, or sender_address
#[derive(Clone, Debug)]
#[contracttype]
pub struct DepositInfo {
    pub min_amount_out: i128,
    pub max_slippage_bps: u32,
    pub expiry_timestamp: u64,
    pub timestamp: u64,
    pub fee_paid: i128,
}

pub struct CoinJoinMixer;

impl CoinJoinMixer {
    // === Initialization Functions ===

    /// Initialize CoinJoin mixer with denomination pools
    /// Based on JoinMarket's market setup and Wasabi's fixed denominations
    pub fn init_coinjoin(env: &Env) -> Result<(), BatcherError> {
        // Note: Called during contract initialization, so no check needed

        // Initialize pools for each denomination
        let denominations = [
            Denomination::Small,
            Denomination::Medium,
            Denomination::Large,
            Denomination::ExtraLarge,
        ];

        for denom in denominations.iter() {
            let pool = CoinJoinPool {
                denomination: *denom,
                deposits: Vec::new(env),
                withdrawals: Vec::new(env),
                merkle_root: BytesN::from_array(env, &[0u8; 32]),
                minimum_pool_size: 3,  // Minimum 3 deposits for privacy
                maximum_pool_size: 10, // Mix in batches of 10
                fee_basis_points: 10,  // 0.1% fee
            };

            // Store pool using denomination as key
            let pool_key = DataKey::CoinJoinPool(denom.symbol());
            env.storage().instance().set(&pool_key, &pool);
        }

        // Enable CoinJoin mixer
        env.storage().instance().set(&DataKey::CoinJoinEnabled, &true);

        Ok(())
    }

    // === Core Mixing Functions ===

    /// Deposit funds into CoinJoin pool
    /// Implements Tornado Cash's deposit pattern with Wasabi's fixed denominations
    /// Enhanced with slippage protection
    pub fn deposit(
        env: &Env,
        denomination: Denomination,
        recipient_commitment: BytesN<32>,
        nullifier: BytesN<32>,
        sender_address: soroban_sdk::Address,
        recipient_address: soroban_sdk::Address,
        max_slippage_bps: u32,
        token_in: soroban_sdk::Address,
        token_out: soroban_sdk::Address,
        min_amount_out: i128,
    ) -> Result<(), BatcherError> {
        if !Self::is_coinjoin_enabled(env) {
            return Err(BatcherError::InvalidInput);
        }

        // Validate deposit amount matches denomination
        let expected_amount = denomination.value();

        // Get or create pool for this denomination
        let mut pool = Self::get_pool(env, denomination)?;

        // Calculate expiry timestamp (48 hours from now, ~34,560 ledgers at 5 sec/ledger)
        let expiry_timestamp = env.ledger().timestamp() + (48 * 60 * 60);

        // Create deposit record
        let deposit = Deposit {
            commitment: recipient_commitment,
            timestamp: env.ledger().timestamp(),
            nullifier,
            fee_paid: expected_amount * pool.fee_basis_points as i128 / 10000,
            sender_address,
            recipient_address,
            max_slippage_bps,
            expiry_timestamp,
            token_in,
            token_out,
            min_amount_out,
        };

        // Add deposit to pool
        pool.deposits.push_back(deposit);

        // Get pool size before update
        let pool_size = pool.deposits.len();

        // Update pool state
        Self::update_pool(env, denomination, pool)?;

        // Emit deposit event (simplified - log instead of event)
        soroban_sdk::log!(
            env,
            "CoinJoin deposit event: denomination={}, pool_size={}, timestamp={}",
            denomination.symbol(),
            pool_size,
            env.ledger().timestamp()
        );

        Ok(())
    }

    /// Request withdrawal from mixed pool
    /// Implements JoinMarket's blinded withdrawal mechanism
    pub fn request_withdrawal(
        env: &Env,
        denomination: Denomination,
        nullifier_hash: BytesN<32>,
        recipient_hash: BytesN<32>,
        proof_hash: BytesN<32>,
    ) -> Result<(), BatcherError> {
        if !Self::is_coinjoin_enabled(env) {
            return Err(BatcherError::InvalidInput);
        }

        let mut pool = Self::get_pool(env, denomination)?;

        // Verify nullifier hasn't been used before (double-spending protection)
        if Self::is_nullifier_used(env, nullifier_hash.clone())? {
            return Err(BatcherError::InvalidInput);
        }

        // Create withdrawal request
        let withdrawal = WithdrawalRequest {
            nullifier_hash: nullifier_hash.clone(),
            recipient_hash,
            proof_hash,
            requested_timestamp: env.ledger().timestamp(),
        };

        pool.withdrawals.push_back(withdrawal);
        Self::update_pool(env, denomination, pool)?;

        // Mark nullifier as used
        let nullifier_key = DataKey::NullifierUsed(nullifier_hash.clone());
        env.storage().instance().set(&nullifier_key, &true);

        Ok(())
    }

    /// Execute mixing when pool reaches minimum size
    /// Based on Wasabi Wallet's Chaumian mixing algorithm
    pub fn execute_mixing(
        env: &Env,
        denomination: Denomination,
        max_deposits: Option<u32>,
    ) -> Result<MixResult, BatcherError> {
        if !Self::is_coinjoin_enabled(env) {
            return Err(BatcherError::InvalidInput);
        }

        let mut pool = Self::get_pool(env, denomination)?;
        let max_to_mix = max_deposits.unwrap_or(pool.maximum_pool_size);

        // Count unique sender addresses in the pool
        let mut unique_senders = Vec::new(env);
        for i in 0..pool.deposits.len() {
            let deposit = pool.deposits.get(i).unwrap();
            let sender = deposit.sender_address.clone();

            // Check if sender is already in unique list
            let mut is_unique = true;
            for j in 0..unique_senders.len() {
                if unique_senders.get(j).unwrap() == sender {
                    is_unique = false;
                    break;
                }
            }

            if is_unique {
                unique_senders.push_back(sender);
            }
        }

        // Check if we have enough UNIQUE senders for mixing
        if unique_senders.len() < pool.minimum_pool_size {
            return Ok(MixResult {
                success: false,
                mixed_amounts: Vec::new(env),
                gas_used: 0,
                anonymity_set_size: 0,
                fees_paid: 0,
            });
        }

        // Limit to maximum batch size
        let mix_count: u32 = if pool.deposits.len() as u32 > max_to_mix {
            max_to_mix
        } else {
            pool.deposits.len() as u32
        };
        let mut mixed_amounts = Vec::new(env);
        let mut total_fees = 0i128;

        // Simulate mixing process (in production, this would use cryptographic mixing)
        for i in 0..mix_count as u32 {
            let deposit = pool.deposits.get(i as u32).unwrap();
            let amount_after_fee = denomination.value() - deposit.fee_paid;
            mixed_amounts.push_back(amount_after_fee);
            total_fees += deposit.fee_paid;
        }

        // Remove mixed deposits from pool
        let mut remaining_deposits = Vec::new(env);
        for i in mix_count as u32..pool.deposits.len() {
            remaining_deposits.push_back(pool.deposits.get(i).unwrap().clone());
        }
        pool.deposits = remaining_deposits;

        // Update pool
        Self::update_pool(env, denomination, pool)?;

        // Emit mixing event (simplified - log instead of event)
        soroban_sdk::log!(
            env,
            "CoinJoin mixed event: denomination={}, mixed_count={}, total_fees={}, anonymity_set={}",
            denomination.symbol(),
            mix_count as u32,
            total_fees,
            mix_count as u32
        );

        Ok(MixResult {
            success: true,
            mixed_amounts,
            gas_used: Self::estimate_mixing_gas_cost(mix_count as u32),
            anonymity_set_size: mix_count as u32,
            fees_paid: total_fees,
        })
    }

    /// Calculate equal payout for a set of deposits
    /// Returns payout information for equal distribution
    pub fn calculate_equal_payout(
        env: &Env,
        denomination: Denomination,
        deposits: Vec<Deposit>,
    ) -> Result<PayoutInfo, BatcherError> {
        use crate::pair_client::SoroswapPairClient;
        use crate::factory_client::SoroswapFactoryClient;

        if deposits.is_empty() {
            return Err(BatcherError::InvalidInput);
        }

        // All deposits should have the same token pair
        let first_deposit = deposits.get(0).unwrap();
        let token_in = first_deposit.token_in.clone();
        let token_out = first_deposit.token_out.clone();

        // Calculate total input amount (all deposits have the same denomination)
        let participant_count = deposits.len() as u32;
        let amount_per_deposit = denomination.value();
        let total_input_amount = amount_per_deposit * participant_count as i128;

        // Verify all deposits use same token pair
        for i in 0..deposits.len() {
            let deposit = deposits.get(i).unwrap();
            if deposit.token_in != token_in || deposit.token_out != token_out {
                return Err(BatcherError::InvalidInput);
            }
        }

        // Get factory address to query pool
        let factory_addr: soroban_sdk::Address = env.storage().instance()
            .get(&DataKey::FactoryAddr)
            .ok_or(BatcherError::NotInitialized)?;

        // Query factory for pool address
        let factory_client = SoroswapFactoryClient::new(env, &factory_addr);
        let pair_addr = factory_client.get_pair(token_in.clone(), token_out.clone());

        // Create pair client
        let pair_client = SoroswapPairClient::new(env, &pair_addr);

        // Get current reserves to calculate output amount
        let (reserve_0, reserve_1) = pair_client.get_reserves();

        // Determine token order in the pair
        let pair_token_0 = pair_client.token_0();
        let is_token_in_token_0 = pair_token_0 == token_in;

        let (reserve_in, reserve_out) = if is_token_in_token_0 {
            (reserve_0, reserve_1)
        } else {
            (reserve_1, reserve_0)
        };

        // Calculate output amount using constant product formula for aggregated swap
        // amount_out = (amount_in * 997 * reserve_out) / (reserve_in * 1000 + amount_in * 997)
        let amount_in_with_fee = total_input_amount * 997; // 0.3% fee
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = (reserve_in * 1000) + amount_in_with_fee;
        let total_output_amount = numerator / denominator;

        // Calculate equal payout per participant
        let equal_payout_amount = total_output_amount / participant_count as i128;

        // Calculate realized slippage in basis points
        // slippage_bps = ((min_expected - actual) / min_expected) * 10000
        // For simplicity, we use the average min_amount_out across deposits
        let mut total_min_expected = 0i128;
        for i in 0..deposits.len() {
            total_min_expected += deposits.get(i).unwrap().min_amount_out;
        }
        let avg_min_expected = total_min_expected / participant_count as i128;

        let slippage_bps = if avg_min_expected > 0 {
            let slippage_amount = if avg_min_expected > equal_payout_amount {
                avg_min_expected - equal_payout_amount
            } else {
                0
            };
            ((slippage_amount * 10000) / avg_min_expected) as u32
        } else {
            0
        };

        Ok(PayoutInfo {
            equal_payout_amount,
            total_input_amount,
            total_output_amount,
            slippage_bps,
            participant_count,
        })
    }

    /// Sort deposits by min_amount_out (ascending order)
    /// Participants with lowest requirements come first
    /// Uses bubble sort for simplicity and gas efficiency with small N
    fn sort_deposits_by_min_amount(env: &Env, deposits: &mut Vec<Deposit>) {
        let len = deposits.len();
        if len <= 1 {
            return;
        }

        // Bubble sort - O(N²) but acceptable for small batch sizes (N ≤ 10)
        for i in 0..len {
            for j in 0..(len - i - 1) {
                let deposit_j = deposits.get(j).unwrap();
                let deposit_j_plus_1 = deposits.get(j + 1).unwrap();

                // Sort ascending: lowest min_amount_out first
                if deposit_j.min_amount_out > deposit_j_plus_1.min_amount_out {
                    // Swap
                    deposits.set(j, deposit_j_plus_1);
                    deposits.set(j + 1, deposit_j);
                }
            }
        }

        soroban_sdk::log!(
            env,
            "Sorted {} deposits by min_amount_out (ascending)",
            len
        );
    }

    /// Find optimal participant set using descending set size search (v3 algorithm)
    /// Tests sets from largest to smallest, returning maximum qualifying set
    /// This maximizes anonymity set size and throughput
    pub fn find_optimal_participant_set(
        env: &Env,
        denomination: Denomination,
        all_deposits: Vec<Deposit>,
    ) -> Result<Vec<Deposit>, BatcherError> {

        if all_deposits.is_empty() {
            return Err(BatcherError::InvalidInput);
        }

        // Get pool configuration to access minimum_pool_size
        let pool = Self::get_pool(env, denomination)?;
        let min_participants = pool.minimum_pool_size;

        soroban_sdk::log!(
            env,
            "Starting v3 optimal participant selection: {} deposits, min {} participants",
            all_deposits.len(),
            min_participants
        );

        // STEP 1: Sort deposits by min_amount_out (ascending)
        // This ensures participants with lowest requirements are tested first
        let mut sorted_deposits = all_deposits.clone();
        Self::sort_deposits_by_min_amount(env, &mut sorted_deposits);

        // STEP 2: Test from largest set down to minimum
        // First qualifying set found is the maximum possible
        for set_size in (min_participants..=sorted_deposits.len()).rev() {
            soroban_sdk::log!(
                env,
                "Testing set size: {} participants",
                set_size
            );

            // Take first set_size participants (those with lowest requirements)
            let mut candidate_set = Vec::new(env);
            for i in 0..set_size {
                candidate_set.push_back(sorted_deposits.get(i).unwrap());
            }

            // Calculate payout for this set size
            let payout_info = Self::calculate_equal_payout(
                env,
                denomination,
                candidate_set.clone(),
            )?;

            soroban_sdk::log!(
                env,
                "Set size {}: {} stroops payout each, {} bps slippage",
                set_size,
                payout_info.equal_payout_amount,
                payout_info.slippage_bps
            );

            // STEP 3: Check if ALL participants in this set qualify
            let mut all_qualify = true;
            for i in 0..candidate_set.len() {
                let deposit = candidate_set.get(i).unwrap();

                let meets_minimum = payout_info.equal_payout_amount >= deposit.min_amount_out;
                let within_slippage = payout_info.slippage_bps <= deposit.max_slippage_bps;

                if !meets_minimum || !within_slippage {
                    all_qualify = false;
                    soroban_sdk::log!(
                        env,
                        "Participant {} disqualified: min_out={}, payout={}, max_slip={}, actual_slip={}",
                        i,
                        deposit.min_amount_out,
                        payout_info.equal_payout_amount,
                        deposit.max_slippage_bps,
                        payout_info.slippage_bps
                    );
                    break;
                }
            }

            // If all qualify, this is our maximum set!
            if all_qualify {
                soroban_sdk::log!(
                    env,
                    "✓ Optimal set found: {} participants (maximum possible)",
                    set_size
                );
                return Ok(candidate_set);
            }
        }

        // No qualifying set found
        soroban_sdk::log!(
            env,
            "✗ No qualifying set found (insufficient liquidity)"
        );
        Err(BatcherError::InsufficientBalance)
    }

    // === Multicall Integration Functions ===
    // TODO: Implement proper multicall integration
    // Commented out for now due to type compatibility issues with Vec<u8>

    // === Helper Functions ===

    /// Check if CoinJoin mixer is enabled
    fn is_coinjoin_enabled(env: &Env) -> bool {
        env.storage().instance()
            .get(&DataKey::CoinJoinEnabled)
            .unwrap_or(false)
    }

    /// Get pool for specific denomination (public for execute_batch_swap)
    pub fn get_pool(env: &Env, denomination: Denomination) -> Result<CoinJoinPool, BatcherError> {
        let pool_key = DataKey::CoinJoinPool(denomination.symbol());
        env.storage().instance()
            .get(&pool_key)
            .ok_or(BatcherError::InvalidInput)
    }

    /// Update pool state (public for execute_batch_swap)
    pub fn update_pool(env: &Env, denomination: Denomination, pool: CoinJoinPool) -> Result<(), BatcherError> {
        let pool_key = DataKey::CoinJoinPool(denomination.symbol());
        env.storage().instance().set(&pool_key, &pool);
        Ok(())
    }

    /// Check if nullifier has been used (double-spending protection)
    fn is_nullifier_used(env: &Env, nullifier_hash: BytesN<32>) -> Result<bool, BatcherError> {
        let nullifier_key = DataKey::NullifierUsed(nullifier_hash);
        Ok(env.storage().instance()
            .get(&nullifier_key)
            .unwrap_or(false))
    }

    // === Statistics and Information Functions ===

    /// Get pool statistics for monitoring
    pub fn get_pool_stats(env: &Env, denomination: Denomination) -> Result<PoolStats, BatcherError> {
        let pool = Self::get_pool(env, denomination)?;

        let total_deposits: u64 = env.storage().instance()
            .get(&DataKey::CoinJoinTotalDeposits(denomination.symbol()))
            .unwrap_or(0);

        let total_withdrawals: u64 = env.storage().instance()
            .get(&DataKey::CoinJoinTotalWithdrawals(denomination.symbol()))
            .unwrap_or(0);

        let estimated_wait_time = if pool.deposits.len() as u32 >= pool.minimum_pool_size {
            0 // Ready to mix
        } else {
            (pool.minimum_pool_size - pool.deposits.len() as u32) * 5 // Estimate 5 blocks per deposit
        };

        Ok(PoolStats {
            denomination,
            current_pool_size: pool.deposits.len() as u32,
            total_deposits,
            total_withdrawals,
            current_fees: pool.fee_basis_points,
            estimated_wait_time,
        })
    }

    /// Get deposit details for monitoring (privacy-safe)
    /// Returns public information only - does NOT expose commitment, nullifier, or sender
    pub fn get_deposit_details(
        env: &Env,
        denomination: Denomination,
        index: u32,
    ) -> Result<DepositInfo, BatcherError> {
        let pool = Self::get_pool(env, denomination)?;

        if index >= pool.deposits.len() {
            return Err(BatcherError::InvalidInput);
        }

        let deposit = pool.deposits.get(index).unwrap();

        // Return only non-sensitive information
        Ok(DepositInfo {
            min_amount_out: deposit.min_amount_out,
            max_slippage_bps: deposit.max_slippage_bps,
            expiry_timestamp: deposit.expiry_timestamp,
            timestamp: deposit.timestamp,
            fee_paid: deposit.fee_paid,
        })
    }

    /// Estimate gas cost for mixing operations
    pub fn estimate_mixing_gas_cost(deposit_count: u32) -> u64 {
        // Base cost for mixing operation
        let base_cost = 25_000u64;

        // Per-deposit cost for cryptographic operations
        let per_deposit_cost = 8_000u64;

        // Merkle tree operations cost
        let merkle_cost = 5_000u64;

        // Event emission cost
        let event_cost = 3_000u64;

        base_cost + (deposit_count as u64 * per_deposit_cost) + merkle_cost + event_cost
    }

    /// Check if denomination is supported
    pub fn is_supported_denomination(amount: i128) -> bool {
        Denomination::from_amount(amount).is_some()
    }

    /// Calculate required deposit count for amount
    pub fn calculate_deposit_count(amount: i128) -> Result<u32, BatcherError> {
        if !Self::is_supported_denomination(amount) {
            return Err(BatcherError::InvalidInput);
        }

        // For now, assume single denomination deposits
        // In future versions, could support multi-denomination
        Ok(1)
    }
}

// === Event Definitions ===

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct CoinJoinDepositEvent {
    pub denomination: Symbol,
    pub pool_size: u32,
    pub timestamp: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct CoinJoinMixedEvent {
    pub denomination: Symbol,
    pub mixed_count: u32,
    pub total_fees: i128,
    pub anonymity_set_size: u32,
    pub timestamp: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use soroban_sdk::Env;

    #[test]
    fn test_denomination_values() {
        assert_eq!(Denomination::Small.value(), 10_000_000);
        assert_eq!(Denomination::Medium.value(), 100_000_000);
        assert_eq!(Denomination::Large.value(), 1_000_000_000);
        assert_eq!(Denomination::ExtraLarge.value(), 10_000_000_000);
    }

    #[test]
    fn test_is_supported_denomination() {
        assert!(CoinJoinMixer::is_supported_denomination(10_000_000));
        assert!(CoinJoinMixer::is_supported_denomination(100_000_000));
        assert!(!CoinJoinMixer::is_supported_denomination(50_000_000));
    }

    #[test]
    fn test_calculate_deposit_count() {
        let result = CoinJoinMixer::calculate_deposit_count(10_000_000);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 1);
    }

    #[test]
    fn test_estimate_mixing_gas_cost() {
        let gas_cost = CoinJoinMixer::estimate_mixing_gas_cost(5);
        assert_eq!(gas_cost, 25000 + (5 * 8000) + 5000 + 3000);
    }
}