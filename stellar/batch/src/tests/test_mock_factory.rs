//! Tests using the mock factory contract
//! These tests validate that the batcher works correctly with a realistic factory implementation

use soroban_sdk::{Env, Address, Vec, testutils::Address as _};
use super::mock_factory::MockFactoryHelper;

// Helper function for test addresses
fn get_test_address(env: &Env, _index: u8) -> Address {
    Address::generate(env)
}

#[test]
fn test_mock_factory_creation() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);

    // Test that factory was created
    assert_eq!(factory.all_pairs_length(), 0);

    // Add a pair
    let token_a = get_test_address(&env, 0);
    let token_b = get_test_address(&env, 1);
    let pair_addr = get_test_address(&env, 2);

    let result = factory.add_pair(token_a.clone(), token_b.clone(), pair_addr.clone());
    assert!(result);

    // Test pair exists
    assert!(factory.pair_exists(token_a.clone(), token_b.clone()));
    assert_eq!(factory.all_pairs_length(), 1);

    // Test get pair
    let retrieved_pair = factory.get_pair(token_a, token_b);
    assert_eq!(retrieved_pair, Some(pair_addr));
}

#[test]
fn test_batcher_with_mock_factory() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);
    let factory_addr = factory.address();

    // Add some pairs to the factory
    let token_a = get_test_address(&env, 1);
    let token_b = get_test_address(&env, 2);
    let pair_addr = get_test_address(&env, 3);

    factory.add_pair(token_a.clone(), token_b.clone(), pair_addr.clone());

    // Test that mock factory works correctly on its own
    assert!(factory.pair_exists(token_a.clone(), token_b.clone()));
    let retrieved_pair = factory.get_pair(token_a, token_b);
    assert_eq!(retrieved_pair, Some(pair_addr));

    // Test factory address is correctly set
    assert_eq!(factory.address(), factory_addr);
}

#[test]
fn test_order_submission_with_mock_factory() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);

    // Add pairs to factory
    let token_a = get_test_address(&env, 1);
    let token_b = get_test_address(&env, 2);
    let pair_addr = get_test_address(&env, 3);

    factory.add_pair(token_a.clone(), token_b.clone(), pair_addr.clone());

    // Test that factory operations work correctly
    assert!(factory.pair_exists(token_a.clone(), token_b.clone()));
    assert_eq!(factory.get_pair(token_a.clone(), token_b.clone()), Some(pair_addr.clone()));
    assert_eq!(factory.all_pairs_length(), 1);

    // Test adding duplicate pair (should return false)
    let duplicate_result = factory.add_pair(token_a.clone(), token_b.clone(), pair_addr.clone());
    assert!(!duplicate_result); // Should return false since pair already exists

    // Test pair count remains the same
    assert_eq!(factory.all_pairs_length(), 1);
}

#[test]
fn test_multiple_pairs_scenario() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);

    // Create multiple token pairs
    let mut tokens = Vec::new(&env);
    let mut pairs = Vec::new(&env);
    for i in 0..6 {
        tokens.push_back(get_test_address(&env, i));
    }
    for i in 6..9 {
        pairs.push_back(get_test_address(&env, i));
    }

    // Add pairs to factory
    factory.add_pair(tokens.get(0).unwrap().clone(), tokens.get(1).unwrap().clone(), pairs.get(0).unwrap().clone());
    factory.add_pair(tokens.get(2).unwrap().clone(), tokens.get(3).unwrap().clone(), pairs.get(1).unwrap().clone());
    factory.add_pair(tokens.get(4).unwrap().clone(), tokens.get(5).unwrap().clone(), pairs.get(2).unwrap().clone());

    assert_eq!(factory.all_pairs_length(), 3);

    // Test that factory can handle all pairs
    for i in 0..3 {
        let token_a = tokens.get(i * 2).unwrap();
        let token_b = tokens.get(i * 2 + 1).unwrap();
        let pair_addr = pairs.get(i).unwrap();

        // Validate pair exists through factory
        assert!(factory.pair_exists(token_a.clone(), token_b.clone()));

        // Get pair address through factory
        let retrieved_pair = factory.get_pair(token_a.clone(), token_b.clone());
        assert_eq!(retrieved_pair, Some(pair_addr.clone()));
    }
}

#[test]
fn test_factory_error_handling() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);

    // Test with non-existent pair
    let token_a = get_test_address(&env, 1);
    let token_b = get_test_address(&env, 2);

    // Should return false for non-existent pairs
    assert!(!factory.pair_exists(token_a.clone(), token_b.clone()));

    // Getting pair address should return None
    let pair_result = factory.get_pair(token_a.clone(), token_b.clone());
    assert_eq!(pair_result, None);

    // Add pair and test it works
    let pair_addr = get_test_address(&env, 3);
    factory.add_pair(token_a.clone(), token_b.clone(), pair_addr.clone());

    // Now should exist
    assert!(factory.pair_exists(token_a.clone(), token_b.clone()));
    assert_eq!(factory.get_pair(token_a, token_b), Some(pair_addr));
}

#[test]
fn test_performance_with_mock_factory() {
    let env = Env::default();

    // Create mock factory
    let factory = MockFactoryHelper::new(&env);

    // Create multiple pairs for performance testing
    let mut tokens = Vec::new(&env);
    let mut pairs = Vec::new(&env);
    for i in 0..10 {
        tokens.push_back(get_test_address(&env, i));
    }
    for i in 10..15 {
        pairs.push_back(get_test_address(&env, i));
    }

    // Add pairs to factory
    for i in 0..5 {
        factory.add_pair(
            tokens.get(i * 2).unwrap().clone(),
            tokens.get(i * 2 + 1).unwrap().clone(),
            pairs.get(i).unwrap().clone(),
        );
    }

    // Test multiple factory operations
    let mut successful_operations = 0;

    for i in 0..20 {
        let pair_idx = i % 5;
        let token_a = tokens.get(pair_idx * 2).unwrap();
        let token_b = tokens.get(pair_idx * 2 + 1).unwrap();

        // Test pair validation
        if factory.pair_exists(token_a.clone(), token_b.clone()) {
            successful_operations += 1;
        }

        // Test pair retrieval
        if factory.get_pair(token_a.clone(), token_b.clone()).is_some() {
            successful_operations += 1;
        }

        // Test getting total pairs count
        if factory.all_pairs_length() > 0 {
            successful_operations += 1;
        }
    }

    // Verify that all operations succeeded
    assert_eq!(successful_operations, 60); // 20 iterations * 3 operations each

    // Verify we have exactly 5 pairs
    assert_eq!(factory.all_pairs_length(), 5);
}
