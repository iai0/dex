use anchor_lang::prelude::*;

declare_id!("uY7scRK6DgtK7Ww9udtDiny7fpyEF324C78PXHnemKP");

#[program]
pub mod factory_stub {
    use super::*;

    /// Registers a pair address for the two token mints. Idempotent.
    pub fn set_pair(ctx: Context<SetPair>, pair_address: Pubkey) -> Result<()> {
        let record = &mut ctx.accounts.pair_record;
        record.token_a = ctx.accounts.token_a.key();
        record.token_b = ctx.accounts.token_b.key();
        record.pair = pair_address;
        record.bump = ctx.bumps.pair_record;
        Ok(())
    }
}

#[derive(Accounts)]
#[instruction()]
pub struct SetPair<'info> {
    /// CHECK: token mint pubkey
    pub token_a: AccountInfo<'info>,
    /// CHECK: token mint pubkey
    pub token_b: AccountInfo<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + PairRecord::LEN,
        seeds = [b"pair", token_a.key().as_ref(), token_b.key().as_ref()],
        bump,
    )]
    pub pair_record: Account<'info, PairRecord>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct PairRecord {
    pub token_a: Pubkey,
    pub token_b: Pubkey,
    pub pair: Pubkey,
    pub bump: u8,
}

impl PairRecord {
    pub const LEN: usize = 32 + 32 + 32 + 1;
}
