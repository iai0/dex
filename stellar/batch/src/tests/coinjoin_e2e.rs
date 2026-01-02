//! End-to-end style CoinJoin flow using in-memory mock factory/pair contracts.

use soroban_sdk::{
    contract, contractimpl,
    testutils::Address as _,
    Address, BytesN, Env, Symbol,
};

use crate::{
    coinjoin::{CoinJoinMixer, Denomination},
    DataKey, SoroSwapBatcher,
};

/// Minimal mock pair contract that returns static reserves/token addresses.
#[contract]
pub struct MockPair;

#[contractimpl]
impl MockPair {
    pub fn __init(env: Env, token_0: Address, token_1: Address, reserve_0: i128, reserve_1: i128) {
        env.storage().instance().set(&Symbol::new(&env, "token_0"), &token_0);
        env.storage().instance().set(&Symbol::new(&env, "token_1"), &token_1);
        env.storage().instance().set(&Symbol::new(&env, "reserve_0"), &reserve_0);
        env.storage().instance().set(&Symbol::new(&env, "reserve_1"), &reserve_1);
    }

    pub fn swap(_env: Env, _amount_0_out: i128, _amount_1_out: i128, _to: Address) {
        // No-op for tests; just satisfies interface.
    }

    pub fn token_0(env: Env) -> Address {
        env.storage().instance().get(&Symbol::new(&env, "token_0")).unwrap()
    }

    pub fn token_1(env: Env) -> Address {
        env.storage().instance().get(&Symbol::new(&env, "token_1")).unwrap()
    }

    pub fn get_reserves(env: Env) -> (i128, i128) {
        let r0: i128 = env.storage().instance().get(&Symbol::new(&env, "reserve_0")).unwrap();
        let r1: i128 = env.storage().instance().get(&Symbol::new(&env, "reserve_1")).unwrap();
        (r0, r1)
    }
}

/// Minimal mock factory contract that always returns a preset pair address.
#[contract]
pub struct MockFactory;

#[contractimpl]
impl MockFactory {
    pub fn __init(env: Env, pair: Address) {
        env.storage().instance().set(&Symbol::new(&env, "pair"), &pair);
    }

    pub fn get_pair(env: Env, _token_a: Address, _token_b: Address) -> Address {
        env.storage().instance().get(&Symbol::new(&env, "pair")).unwrap()
    }
}

#[test]
fn coinjoin_flow_mixes_three_participants() {
    let env = Env::default();

    // Register mock pair and factory.
    let token_a = Address::generate(&env);
    let token_b = Address::generate(&env);
    let pair = env.register(MockPair, ());
    env.as_contract(&pair, || {
        MockPair::__init(env.clone(), token_a.clone(), token_b.clone(), 1_000_000_000, 1_000_000_000);
    });

    let factory = env.register(MockFactory, ());
    env.as_contract(&factory, || {
        MockFactory::__init(env.clone(), pair.clone());
    });

    // Register batch contract and initialize.
    let contract_id = env.register(SoroSwapBatcher, ());
    let owner = Address::generate(&env);
    let router = Address::generate(&env);

    env.as_contract(&contract_id, || {
        SoroSwapBatcher::initialize(env.clone(), owner, factory.clone(), router).unwrap();
    });

    // Prepare three deposits for the smallest denomination.
    let denom = Denomination::Small;
    let receivers: [Address; 3] = [
        Address::generate(&env),
        Address::generate(&env),
        Address::generate(&env),
    ];
    let senders: [Address; 3] = [
        Address::generate(&env),
        Address::generate(&env),
        Address::generate(&env),
    ];

    env.as_contract(&contract_id, || {
        for i in 0..3 {
            let commitment = BytesN::from_array(&env, &[i as u8; 32]);
            let nullifier = BytesN::from_array(&env, &[(i + 10) as u8; 32]);
            CoinJoinMixer::deposit(
                &env,
                denom,
                commitment,
                nullifier,
                senders[i].clone(),
                receivers[i].clone(),
                50, // max slippage bps
                token_a.clone(),
                token_b.clone(),
                denom.value(), // min_amount_out placeholder
            )
            .unwrap();
        }

        // Execute mixing now that minimum participants are present.
        let mix_result = CoinJoinMixer::execute_mixing(&env, denom, Some(3)).unwrap();
        assert!(mix_result.success);
        assert_eq!(mix_result.anonymity_set_size, 3);

        // Pool size should now be zero for this denomination.
        let pool_stats = CoinJoinMixer::get_pool_stats(&env, denom).unwrap();
        assert_eq!(pool_stats.current_pool_size, 0);
    });

    // Ensure factory address persisted.
    env.as_contract(&contract_id, || {
        let stored_factory: Address = env.storage().instance().get(&DataKey::FactoryAddr).unwrap();
        assert_eq!(stored_factory, factory);
    });
}
