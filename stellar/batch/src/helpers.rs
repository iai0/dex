// src/helpers.rs
// Common helper functions used across modules

use soroban_sdk::{Env, Address};

/// Check if the contract is initialized
/// This is a centralized helper function used by all modules
pub fn is_initialized(env: &Env) -> bool {
    env.storage().instance()
        .get::<_, Address>(&crate::DataKey::Owner)
        .is_some()
}