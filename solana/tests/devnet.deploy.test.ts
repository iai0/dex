import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Batch } from "../target/types/batch";
import { FactoryStub } from "../target/types/factory_stub";
import { PairStub } from "../target/types/pair_stub";

const BATCH_PROGRAM_ID = new anchor.web3.PublicKey(
  "2uDexdyb8hj7R1nrR9ESEci831Urbag5Rq12TzgZEAZq"
);
const FACTORY_PROGRAM_ID = new anchor.web3.PublicKey(
  "uY7scRK6DgtK7Ww9udtDiny7fpyEF324C78PXHnemKP"
);
const PAIR_PROGRAM_ID = new anchor.web3.PublicKey(
  "6Wq5RBNnszrhQiR5QBbgZGgHPthLAhot2miZ1qDddKci"
);
const UPGRADEABLE_LOADER = new anchor.web3.PublicKey(
  "BPFLoaderUpgradeab1e11111111111111111111111"
);

describe("devnet deployment checks", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const connection = provider.connection;

  const batch = anchor.workspace.Batch as Program<Batch>;
  const factory = anchor.workspace.FactoryStub as Program<FactoryStub>;
  const pair = anchor.workspace.PairStub as Program<PairStub>;

  it("workspace program IDs match Anchor.toml", () => {
    const workspaceIds = [
      batch.programId.toBase58(),
      factory.programId.toBase58(),
      pair.programId.toBase58(),
    ];
    const expected = [
      BATCH_PROGRAM_ID.toBase58(),
      FACTORY_PROGRAM_ID.toBase58(),
      PAIR_PROGRAM_ID.toBase58(),
    ];
    if (workspaceIds.join() !== expected.join()) {
      throw new Error(
        `Program IDs mismatch.\nWorkspace: ${workspaceIds.join(
          ", "
        )}\nExpected: ${expected.join(", ")}`
      );
    }
  });

  it("programs are deployed & executable on devnet", async () => {
    const ids = [
      { name: "batch", id: BATCH_PROGRAM_ID },
      { name: "factory_stub", id: FACTORY_PROGRAM_ID },
      { name: "pair_stub", id: PAIR_PROGRAM_ID },
    ];

    for (const { name, id } of ids) {
      const info = await connection.getAccountInfo(id);
      if (!info) {
        throw new Error(`${name} program account not found on devnet`);
      }
      if (!info.executable) {
        throw new Error(`${name} account exists but is not executable`);
      }
      if (!info.owner.equals(UPGRADEABLE_LOADER)) {
        throw new Error(
          `${name} owner mismatch (got ${info.owner.toBase58()})`
        );
      }
    }
  });
});
