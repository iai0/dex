use anchor_lang::prelude::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    token::{self, Mint, Token, TokenAccount, Transfer},
};

declare_id!("6Wq5RBNnszrhQiR5QBbgZGgHPthLAhot2miZ1qDddKci");

#[program]
pub mod pair_stub {
    use super::*;

    /// Initialize a stub pair with fixed reserves and vault.
    pub fn init_pair(
        ctx: Context<InitPair>,
        reserve_0: u64,
        reserve_1: u64,
    ) -> Result<()> {
        let pair = &mut ctx.accounts.pair;
        pair.authority = ctx.accounts.authority.key();
        pair.token_0 = ctx.accounts.mint_0.key();
        pair.token_1 = ctx.accounts.mint_1.key();
        pair.reserve_0 = reserve_0;
        pair.reserve_1 = reserve_1;
        pair.vault_0 = ctx.accounts.vault_0.key();
        pair.vault_1 = ctx.accounts.vault_1.key();
        pair.bump = ctx.bumps.pair;
        Ok(())
    }

    /// Update reserves (for testing scenarios).
    pub fn set_reserves(ctx: Context<SetReserves>, reserve_0: u64, reserve_1: u64) -> Result<()> {
        let pair = &mut ctx.accounts.pair;
        require_keys_eq!(pair.authority, ctx.accounts.authority.key(), PairError::Unauthorized);
        pair.reserve_0 = reserve_0;
        pair.reserve_1 = reserve_1;
        Ok(())
    }

    /// Stub swap: transfers provided outputs from vaults to the recipient.
    pub fn swap(
        ctx: Context<Swap>,
        amount_0_out: u64,
        amount_1_out: u64,
    ) -> Result<()> {
        let pair = &ctx.accounts.pair;
        // Pay out from vaults; this is a stub and does not update reserves.
        if amount_0_out > 0 {
            let seeds = &[b"pair", pair.token_0.as_ref(), pair.token_1.as_ref(), &[pair.bump]];
            let signer = &[&seeds[..]];
            let cpi_accounts = Transfer {
                from: ctx.accounts.vault_0.to_account_info(),
                to: ctx.accounts.to_0.to_account_info(),
                authority: ctx.accounts.pair.to_account_info(),
            };
            let cpi_ctx =
                CpiContext::new_with_signer(ctx.accounts.token_program.to_account_info(), cpi_accounts, signer);
            token::transfer(cpi_ctx, amount_0_out)?;
        }
        if amount_1_out > 0 {
            let seeds = &[b"pair", pair.token_0.as_ref(), pair.token_1.as_ref(), &[pair.bump]];
            let signer = &[&seeds[..]];
            let cpi_accounts = Transfer {
                from: ctx.accounts.vault_1.to_account_info(),
                to: ctx.accounts.to_1.to_account_info(),
                authority: ctx.accounts.pair.to_account_info(),
            };
            let cpi_ctx =
                CpiContext::new_with_signer(ctx.accounts.token_program.to_account_info(), cpi_accounts, signer);
            token::transfer(cpi_ctx, amount_1_out)?;
        }
        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitPair<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    pub mint_0: Account<'info, Mint>,
    pub mint_1: Account<'info, Mint>,
    #[account(
        init,
        payer = authority,
        space = 8 + PairState::LEN,
        seeds = [b"pair", mint_0.key().as_ref(), mint_1.key().as_ref()],
        bump
    )]
    pub pair: Account<'info, PairState>,
    #[account(
        init,
        payer = authority,
        associated_token::mint = mint_0,
        associated_token::authority = pair
    )]
    pub vault_0: Account<'info, TokenAccount>,
    #[account(
        init,
        payer = authority,
        associated_token::mint = mint_1,
        associated_token::authority = pair
    )]
    pub vault_1: Account<'info, TokenAccount>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct SetReserves<'info> {
    #[account(mut, has_one = authority)]
    pub pair: Account<'info, PairState>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Swap<'info> {
    #[account(
        seeds = [b"pair", pair.token_0.as_ref(), pair.token_1.as_ref()],
        bump = pair.bump
    )]
    pub pair: Account<'info, PairState>,
    #[account(mut)]
    pub vault_0: Account<'info, TokenAccount>,
    #[account(mut)]
    pub vault_1: Account<'info, TokenAccount>,
    #[account(mut)]
    pub to_0: Account<'info, TokenAccount>,
    #[account(mut)]
    pub to_1: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[account]
pub struct PairState {
    pub authority: Pubkey,
    pub token_0: Pubkey,
    pub token_1: Pubkey,
    pub reserve_0: u64,
    pub reserve_1: u64,
    pub vault_0: Pubkey,
    pub vault_1: Pubkey,
    pub bump: u8,
}

impl PairState {
    pub const LEN: usize = 32 + 32 + 32 + 8 + 8 + 32 + 32 + 1;
}

#[error_code]
pub enum PairError {
    #[msg("Unauthorized")]
    Unauthorized,
}
