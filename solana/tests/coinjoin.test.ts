import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Batch } from "../target/types/batch";

// This is a placeholder smoke test to show how to load the program on devnet.
// Actual flow (init_config, init_pool, deposit, execute_mixing) can be added
// once keys/mints are provisioned on devnet.
describe("batch coinjoin (devnet placeholder)", () => {
  anchor.setProvider(anchor.AnchorProvider.env());

  const program = anchor.workspace.Batch as Program<Batch>;

  it("loads the program ID", async () => {
    // Ensure the workspace program is reachable.
    console.log("Batch program ID:", program.programId.toBase58());
  });
});
