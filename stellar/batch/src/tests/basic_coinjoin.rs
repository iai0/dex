//! Basic contract tests focused on initialization and CoinJoin wiring.

use soroban_sdk::{testutils::Address as _, Address, Env, Symbol};
use crate::{BatcherError, SoroSwapBatcher};

#[test]
fn initialize_sets_core_state_and_enables_coinjoin() {
    let env = Env::default();
    let contract_id = env.register(SoroSwapBatcher, ());

    let owner = Address::generate(&env);
    let factory = Address::generate(&env);
    let router = Address::generate(&env);

    env.as_contract(&contract_id, || {
        SoroSwapBatcher::initialize(
            env.clone(),
            owner.clone(),
            factory.clone(),
            router.clone(),
        )
        .expect("initialization should succeed");

        assert!(SoroSwapBatcher::is_coinjoin_enabled(env.clone()));
        assert_eq!(SoroSwapBatcher::get_owner(env.clone()).unwrap(), owner);
        assert_eq!(SoroSwapBatcher::get_factory(env.clone()).unwrap(), factory);
        assert_eq!(SoroSwapBatcher::get_router(env.clone()).unwrap(), router);
    });
}

#[test]
fn double_initialize_fails() {
    let env = Env::default();
    let contract_id = env.register(SoroSwapBatcher, ());

    let owner = Address::generate(&env);
    let factory = Address::generate(&env);
    let router = Address::generate(&env);

    env.as_contract(&contract_id, || {
        SoroSwapBatcher::initialize(
            env.clone(),
            owner.clone(),
            factory.clone(),
            router.clone(),
        )
        .unwrap();

        let err = SoroSwapBatcher::initialize(env.clone(), owner, factory, router)
            .expect_err("second init should fail");
        assert!(matches!(err, BatcherError::AlreadyInitialized));
    });
}

#[test]
fn coinjoin_stats_available_post_init() {
    let env = Env::default();
    let contract_id = env.register(SoroSwapBatcher, ());

    let owner = Address::generate(&env);
    let factory = Address::generate(&env);
    let router = Address::generate(&env);

    env.as_contract(&contract_id, || {
        SoroSwapBatcher::initialize(env.clone(), owner, factory, router).unwrap();

        let (pool_size, fee_bps, wait_time) = SoroSwapBatcher::get_coinjoin_stats(
            env.clone(),
            Symbol::new(&env, "10"),
        )
        .unwrap();

        assert_eq!(pool_size, 0);
        assert_eq!(fee_bps, 10); // default fee basis points from CoinJoin init
        assert_eq!(wait_time, 15); // minimum_pool_size(3) * 5 blocks wait
    });
}
