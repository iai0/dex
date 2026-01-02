// contracts/batch/src/error.rs
// Simplified error handling for SoroSwap Batch contract
// Based on Soroban error handling best practices

use soroban_sdk::contracterror;

/// Comprehensive error type for batch contract operations
#[contracterror]
#[derive(Debug, Copy, Clone, PartialEq)]
pub enum BatcherError {
    /// Core functionality errors
    InvalidInput = 1,
    InsufficientBalance = 2,
    Unauthorized = 3,
    ContractPaused = 4,
    InternalError = 5,

    /// Initialization errors
    AlreadyInitialized = 6,
    NotInitialized = 7,

    /// Factory and pair errors
    FactoryNotConnected = 8,
    PairNotFound = 9,
    FactoryError = 10,
    InvalidPairAddress = 11,

    /// Commit-reveal errors
    CommitNotFound = 12,
    CommitExpired = 13,
    InvalidCommitHash = 14,
    AlreadyRevealed = 15,
    CommitRevealDisabled = 16,

    /// MEV protection errors
    MEVProtectionDisabled = 17,
    OrderTooEarly = 18,
    OrderTooLate = 19,
    ExecutionWindowFull = 20,
    QueueFull = 21,
    PriorityConflict = 22,

    /// Order errors
    OrderNotFound = 23,
}

/// Error categories for organized error handling
#[derive(Debug, Clone, PartialEq)]
pub enum ErrorCategory {
    Initialization,
    Factory,
    Validation,
    Permission,
    CommitReveal,
    MEVProtection,
    Order,
    System,
}

impl BatcherError {
    /// Get error category for better error handling
    pub fn category(&self) -> ErrorCategory {
        match self {
            BatcherError::InvalidInput | BatcherError::InsufficientBalance => ErrorCategory::Validation,
            BatcherError::Unauthorized | BatcherError::ContractPaused => ErrorCategory::Permission,
            BatcherError::AlreadyInitialized | BatcherError::NotInitialized => ErrorCategory::Initialization,
            BatcherError::FactoryNotConnected | BatcherError::PairNotFound |
            BatcherError::FactoryError | BatcherError::InvalidPairAddress => ErrorCategory::Factory,
            BatcherError::CommitNotFound | BatcherError::CommitExpired |
            BatcherError::InvalidCommitHash | BatcherError::AlreadyRevealed |
            BatcherError::CommitRevealDisabled => ErrorCategory::CommitReveal,
            BatcherError::MEVProtectionDisabled | BatcherError::OrderTooEarly |
            BatcherError::OrderTooLate | BatcherError::ExecutionWindowFull |
            BatcherError::QueueFull | BatcherError::PriorityConflict => ErrorCategory::MEVProtection,
            BatcherError::OrderNotFound => ErrorCategory::Order,
            BatcherError::InternalError => ErrorCategory::System,
        }
    }

    /// Check if error is recoverable (can be retried)
    pub fn is_recoverable(&self) -> bool {
        match self {
            BatcherError::InvalidInput |
            BatcherError::InsufficientBalance |
            BatcherError::OrderTooEarly |
            BatcherError::ExecutionWindowFull |
            BatcherError::QueueFull => true,
            _ => false,
        }
    }

    /// Get user-friendly error message
    pub fn user_message(&self) -> &'static str {
        match self {
            BatcherError::InvalidInput => "Invalid input parameters",
            BatcherError::InsufficientBalance => "Insufficient balance",
            BatcherError::Unauthorized => "Unauthorized access",
            BatcherError::ContractPaused => "Contract is currently paused",
            BatcherError::InternalError => "Internal system error",
            _ => "Unknown error occurred",
        }
    }
}