use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

declare_id!("2uDexdyb8hj7R1nrR9ESEci831Urbag5Rq12TzgZEAZq");

/// Fixed denominations expressed in the SPL token's base units.
/// These mirror the Soroban contract defaults (stroops -> base units here).
pub const DENOM_SMALL: u64 = 10_000_000;      // 1 unit (e.g., 1 XLM-equivalent)
pub const DENOM_MEDIUM: u64 = 100_000_000;    // 10 units
pub const DENOM_LARGE: u64 = 1_000_000_000;   // 100 units
pub const DENOM_XL: u64 = 2_000_000_000;      // 200 units

pub const POOL_SEED: &[u8] = b"pool";
pub const CONFIG_SEED: &[u8] = b"config";

#[program]
pub mod batch {
    use super::*;

    /// Initialize global config (owner, factory, router). One-time.
    pub fn initialize_config(
        ctx: Context<InitializeConfig>,
        factory: Pubkey,
        router: Pubkey,
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.owner = ctx.accounts.payer.key();
        config.factory = factory;
        config.router = router;
        config.bump = ctx.bumps.config;
        Ok(())
    }

    /// Create a CoinJoin pool for a specific denomination and mint.
    pub fn init_pool(
        ctx: Context<InitPool>,
        denomination: u64,
        fee_bps: u16,
        min_pool_size: u32,
        max_pool_size: u32,
    ) -> Result<()> {
        require!(is_supported_denom(denomination), BatchError::UnsupportedDenomination);
        require!(min_pool_size >= 2, BatchError::InvalidConfig);
        require!(max_pool_size >= min_pool_size, BatchError::InvalidConfig);

        let pool = &mut ctx.accounts.pool;
        pool.config = ctx.accounts.config.key();
        pool.mint = ctx.accounts.mint.key();
        pool.vault = ctx.accounts.vault.key();
        pool.denomination = denomination;
        pool.fee_bps = fee_bps;
        pool.min_pool_size = min_pool_size;
        pool.max_pool_size = max_pool_size;
        pool.current_pool_size = 0;
        pool.total_deposits = 0;
        pool.total_withdrawals = 0;
        pool.bump = ctx.bumps.pool;
        Ok(())
    }

    /// Deposit funds into the pool vault; records participant count.
    pub fn deposit(ctx: Context<Deposit>) -> Result<()> {
        let pool = &mut ctx.accounts.pool;
        require!(ctx.accounts.mint.key() == pool.mint, BatchError::MintMismatch);
        require!(ctx.accounts.vault.key() == pool.vault, BatchError::VaultMismatch);

        // Transfer SPL tokens from depositor into the pool vault PDA.
        let cpi_accounts = Transfer {
            from: ctx.accounts.depositor_token.to_account_info(),
            to: ctx.accounts.vault.to_account_info(),
            authority: ctx.accounts.depositor.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);
        token::transfer(cpi_ctx, pool.denomination)?;

        pool.current_pool_size = pool
            .current_pool_size
            .checked_add(1)
            .ok_or(BatchError::MathOverflow)?;
        pool.total_deposits = pool
            .total_deposits
            .checked_add(1)
            .ok_or(BatchError::MathOverflow)?;

        Ok(())
    }

    /// Execute mixing: transfer one denomination to each recipient token account provided in remaining accounts.
    /// Remaining accounts must be SPL token accounts with mint == pool.mint.
    pub fn execute_mixing(ctx: Context<ExecuteMixing>) -> Result<()> {
        // Coerce the context lifetimes so the typed accounts and remaining accounts share one scope.
        let ctx: anchor_lang::context::Context<'_, '_, '_, '_, ExecuteMixing<'_>> =
            unsafe { std::mem::transmute(ctx) };

        let recipient_count = ctx.remaining_accounts.len() as u32;

        let pool_values = {
            let pool = &ctx.accounts.pool;
            (
                pool.denomination,
                pool.bump,
                pool.min_pool_size,
                pool.max_pool_size,
                pool.current_pool_size,
                pool.mint,
            )
        };

        let (denom, pool_bump, min_pool_size, max_pool_size, current_pool_size, pool_mint) =
            pool_values;

        require!(recipient_count >= min_pool_size, BatchError::NotEnoughParticipants);
        require!(recipient_count <= max_pool_size, BatchError::TooManyParticipants);
        require!(recipient_count == current_pool_size, BatchError::ParticipantMismatch);

        let seeds = &[POOL_SEED, &denom.to_le_bytes(), &[pool_bump]];
        let signer_seeds = &[&seeds[..]];

        let vault_info = ctx.accounts.vault.to_account_info();
        let pool_info = ctx.accounts.pool.to_account_info();
        let token_program_info = ctx.accounts.token_program.to_account_info();

        for recipient_info in ctx.remaining_accounts.iter() {
            // Validate each recipient is an SPL token account for the same mint.
            let recipient_token = Account::<TokenAccount>::try_from(recipient_info)
                .map_err(|_| BatchError::InvalidRecipient)?;
            require!(
                recipient_token.mint == pool_mint,
                BatchError::InvalidRecipient
            );

            let cpi_accounts = Transfer {
                from: vault_info.clone(),
                to: recipient_info.clone(),
                authority: pool_info.clone(),
            };
            let cpi_ctx = CpiContext::new_with_signer(
                token_program_info.clone(),
                cpi_accounts,
                signer_seeds,
            );
            token::transfer(cpi_ctx, denom)?;
        }

        let pool = &mut ctx.accounts.pool;
        pool.total_withdrawals = pool
            .total_withdrawals
            .checked_add(recipient_count.into())
            .ok_or(BatchError::MathOverflow)?;
        pool.current_pool_size = 0;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeConfig<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + Config::LEN,
        seeds = [CONFIG_SEED],
        bump
    )]
    pub config: Account<'info, Config>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(denomination: u64)]
pub struct InitPool<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        seeds = [CONFIG_SEED],
        bump = config.bump
    )]
    pub config: Account<'info, Config>,
    #[account(
        init,
        payer = payer,
        space = 8 + Pool::LEN,
        seeds = [POOL_SEED, &denomination.to_le_bytes()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    pub mint: Account<'info, Mint>,
    #[account(
        init,
        payer = payer,
        associated_token::mint = mint,
        associated_token::authority = pool
    )]
    pub vault: Account<'info, TokenAccount>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, anchor_spl::associated_token::AssociatedToken>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut)]
    pub pool: Account<'info, Pool>,
    pub mint: Account<'info, Mint>,
    #[account(
        mut,
        associated_token::mint = mint,
        associated_token::authority = pool
    )]
    pub vault: Account<'info, TokenAccount>,
    #[account(mut)]
    pub depositor: Signer<'info>,
    #[account(
        mut,
        constraint = depositor_token.mint == mint.key(),
        constraint = depositor_token.owner == depositor.key()
    )]
    pub depositor_token: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct ExecuteMixing<'info> {
    #[account(mut)]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        constraint = vault.key() == pool.vault,
        constraint = vault.mint == pool.mint
    )]
    pub vault: Account<'info, TokenAccount>,
    #[account(address = pool.mint)]
    pub mint: Account<'info, Mint>,
    pub token_program: Program<'info, Token>,
}

#[account]
pub struct Config {
    pub owner: Pubkey,
    pub factory: Pubkey,
    pub router: Pubkey,
    pub bump: u8,
}

impl Config {
    pub const LEN: usize = 32 + 32 + 32 + 1;
}

#[account]
pub struct Pool {
    pub config: Pubkey,
    pub mint: Pubkey,
    pub vault: Pubkey,
    pub denomination: u64,
    pub fee_bps: u16,
    pub min_pool_size: u32,
    pub max_pool_size: u32,
    pub current_pool_size: u32,
    pub total_deposits: u64,
    pub total_withdrawals: u64,
    pub bump: u8,
}

impl Pool {
    pub const LEN: usize = 32 + 32 + 32 + 8 + 2 + 4 + 4 + 4 + 8 + 8 + 1;
}

#[error_code]
pub enum BatchError {
    #[msg("Unsupported denomination")]
    UnsupportedDenomination,
    #[msg("Invalid pool configuration")]
    InvalidConfig,
    #[msg("Math overflow")]
    MathOverflow,
    #[msg("Not enough participants")]
    NotEnoughParticipants,
    #[msg("Too many participants")]
    TooManyParticipants,
    #[msg("Participant mismatch")]
    ParticipantMismatch,
    #[msg("Mint mismatch")]
    MintMismatch,
    #[msg("Vault mismatch")]
    VaultMismatch,
    #[msg("Invalid recipient account")]
    InvalidRecipient,
}

fn is_supported_denom(amount: u64) -> bool {
    matches!(
        amount,
        DENOM_SMALL | DENOM_MEDIUM | DENOM_LARGE | DENOM_XL
    )
}
