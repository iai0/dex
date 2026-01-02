//! Mock factory contract for testing SoroSwapBatcher
//! This implements the minimal interface needed for testing

use soroban_sdk::{contract, contractimpl, Address, Env, Map, Symbol, testutils::Address as _};

pub struct SoroswapFactoryContract;

#[contract]
pub struct SoroswapFactory;

#[contractimpl]
impl SoroswapFactory {
    /// Create a new factory instance
    pub fn __init(env: Env, fee_to_setter: Address) {
        // Store the fee setter
        env.storage().instance().set(&Symbol::new(&env, "fee_to_setter"), &fee_to_setter);
    }

    /// Check if a pair exists for the given tokens
    pub fn pair_exists(env: Env, token_a: Address, token_b: Address) -> bool {
        // Create a consistent key for the pair (sort addresses to ensure consistency)
        let pair_key = if token_a < token_b {
            (token_a, token_b)
        } else {
            (token_b, token_a)
        };

        // Check if the pair exists in storage
        env.storage().instance()
            .get(&Symbol::new(&env, "pairs"))
            .unwrap_or_else(|| Map::<(Address, Address), Address>::new(&env))
            .contains_key(pair_key)
    }

    /// Get the pair address for the given tokens
    pub fn get_pair(env: Env, token_a: Address, token_b: Address) -> Option<Address> {
        // Create a consistent key for the pair
        let pair_key = if token_a < token_b {
            (token_a, token_b)
        } else {
            (token_b, token_a)
        };

        // Get the pairs map from storage
        let pairs: Map<(Address, Address), Address> = env.storage().instance()
            .get(&Symbol::new(&env, "pairs"))
            .unwrap_or_else(|| Map::<(Address, Address), Address>::new(&env));

        pairs.get(pair_key)
    }

    /// Create a new pair (for testing purposes)
    pub fn create_pair(env: Env, token_a: Address, token_b: Address, pair_address: Address) -> bool {
        // Create a consistent key for the pair
        let pair_key = if token_a < token_b {
            (token_a, token_b)
        } else {
            (token_b, token_a)
        };

        // Get existing pairs or create new map
        let mut pairs: Map<(Address, Address), Address> = env.storage().instance()
            .get(&Symbol::new(&env, "pairs"))
            .unwrap_or_else(|| Map::<(Address, Address), Address>::new(&env));

        // Add the pair if it doesn't exist
        if !pairs.contains_key(pair_key.clone()) {
            pairs.set(pair_key, pair_address);
            env.storage().instance().set(&Symbol::new(&env, "pairs"), &pairs);
            true
        } else {
            false
        }
    }

    /// Get the number of pairs (for testing)
    pub fn all_pairs_length(env: Env) -> u32 {
        let pairs: Map<(Address, Address), Address> = env.storage().instance()
            .get(&Symbol::new(&env, "pairs"))
            .unwrap_or_else(|| Map::<(Address, Address), Address>::new(&env));

        pairs.len()
    }

    /// Get fee setter (for completeness)
    pub fn fee_to_setter(env: Env) -> Address {
        env.storage().instance()
            .get(&Symbol::new(&env, "fee_to_setter"))
            .unwrap_or_else(|| Address::generate(&env))
    }
}

/// Test helper for managing the mock factory
pub struct MockFactoryHelper {
    env: Env,
    factory_address: Address,
}

impl MockFactoryHelper {
    /// Create a new mock factory helper
    pub fn new(env: &Env) -> Self {
        // Register the factory contract
        let factory_address = env.register(SoroswapFactory, ());

        // Initialize the factory
        let fee_setter = Address::generate(env);
        env.as_contract(&factory_address, || {
            SoroswapFactory::__init(env.clone(), fee_setter);
        });

        Self {
            env: env.clone(),
            factory_address,
        }
    }

    /// Get the factory address
    pub fn address(&self) -> Address {
        self.factory_address.clone()
    }

    /// Add a pair to the factory
    pub fn add_pair(&self, token_a: Address, token_b: Address, pair_address: Address) -> bool {
        self.env.as_contract(&self.factory_address, || {
            SoroswapFactory::create_pair(self.env.clone(), token_a, token_b, pair_address)
        })
    }

    /// Check if a pair exists
    pub fn pair_exists(&self, token_a: Address, token_b: Address) -> bool {
        self.env.as_contract(&self.factory_address, || {
            SoroswapFactory::pair_exists(self.env.clone(), token_a, token_b)
        })
    }

    /// Get a pair address
    pub fn get_pair(&self, token_a: Address, token_b: Address) -> Option<Address> {
        self.env.as_contract(&self.factory_address, || {
            SoroswapFactory::get_pair(self.env.clone(), token_a, token_b)
        })
    }

    /// Get the number of pairs
    pub fn all_pairs_length(&self) -> u32 {
        self.env.as_contract(&self.factory_address, || {
            SoroswapFactory::all_pairs_length(self.env.clone())
        })
    }
}