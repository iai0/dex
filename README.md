# darkstar-public — security analysis workspace

Purpose
- Snapshot of Solana and Stellar batch/coinjoin implementations for security review.
- Focus on core contract logic, on-chain data flows, and end-to-end token movement.

Layout
- `solana/`: Anchor programs (`batch`, `factory_stub`, `pair_stub`) plus devnet E2E tests and helper scripts.
- `stellar/`: Rust batch/coinjoin module with integration tests and snapshot fixtures.

Helpful starting points
- Solana program IDs and devnet setup: `solana/README.md`.
- Shared devnet mint/keypairs for SPL tests: `solana/tests/devnet.fixtures.ts`.
- Stellar CoinJoin guide: `stellar/batch/COINJOIN_TESTING_GUIDE.md`.
- Snapshot expectations for Stellar tests: `stellar/batch/test_snapshots/`.

Notes for auditors
- Tests target devnet (Solana) and bundled fixtures (Stellar); no local validators are started by default.
- No secrets beyond public devnet test keys are stored here.
- See per-folder READMEs for build/test commands; prefer read-only checks unless mutations are required.
