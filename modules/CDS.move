address 0xDF1 {

module MyToken {
    struct T {}
}
}

address 0x1 {

// 1. sXFI must be present in Oracle module Oracle::get_price<sXFI, ETH>
// 2.

module SXFI {
    struct T {}
}

module CDS {

    use 0x1::SXFI::T as SXFI;
    use 0x1::Signer;
    use 0x1::Account;
    use 0x1::Dfinance;

    const COMMISSION : u8 = 100;
    const MARGIN_CALL : u8 = 66;   // divided by hundred Loan-to-Value 1-100
    const TOKEN_DECIMALS : u8 = 8; // or 0 for non-fungible

    // the less Loan-to-value;
    // the more safer is the game;
    // the less amount of sXFI I get;

    // formulae for sXFI:
    // +-------------------------------+
    // | ETH * ETH_SXFI * LTV/MC / 100 |
    // +-------------------------------+
    // ETH - collateral
    // ETH_SXFI - rate
    // LTV - safe rate (below 100)

    const ERR_NO_COLLATERAL : u64 = 101;

    /// Token here disallows using this collateral at owner address
    /// without prepublished token. While providing type-binding
    /// for token holders to get access to locked asset
    resource struct T<Collateral, Token: copyable>{
        locked: Dfinance::T<Collateral>,
        token_amount: u128,
        margin_call: u8,
        // set timestamp for deal end
    }

    public fun create<Collateral, Token: copyable>(
        account: &signer,
        collateral: Dfinance::T<Collateral>
    ) {

        assert(Dfinance::value(&collateral) != 0, ERR_NO_COLLATERAL);

        let total_supply = 100;

        let owner = Signer::address_of(account);
        let token = Dfinance::create_token<Token>( // can be called bond? bearer bonds? WTF? Tranche
            account,
            total_supply,
            TOKEN_DECIMALS,
            b"CDS_TOKEN"
        );

        // CALCULATE RESULTS

        let amount = 10000;

        // formulae for sXFI:
        // +-------------------------------+
        // | ETH * ETH_SXFI * LTV/MC / 100 |
        // +-------------------------------+
        // ETH - collateral
        // ETH_SXFI - rate
        // LTV - safe rate (below 100)


        let sxfi = mint_sxfi(amount); // can only be minted by 0x1
                                      // pool of sxfi need to be existent


        Account::deposit_to_sender<Dfinance::Token<Token>>(account, token);
        Account::deposit_to_sender<SXFI>(account, sxfi);

        // Event::emit<CDS_DEAL_MADE>
        // Event::emit<CDS_TOKEN_ISSUED>
    }

    // It's no refund story, godamnit
    // When margin call reached, following happens
    public fun closey_dealio<Collateral, Token: copyable>(
        account: &signer,
    ) {
        assert(Signer::address_of(account) == 0x1, 0);

        // deal is closed by time
        // some amount of ETH is returned to the bruh, sXFI is destroyed from his account
        // some amount is store

        // Scenario 1. - Margin Call - USER lost, SYSTEM and INVESTORS win
        //
        // if deal is closed by margin call;
        // 0x1 locks the dealio;
        // his ETH is divided by token holders;
        // he keeps the premium and sXFI;
        // token holders can exchange their tokens for stored value;

        // Scenario 2. - Time Limit - Winning for USER
        //
        // deal is closed w/o margin call reached;
        // 0x1 locks the dealio;
        // user can return up to TAKEN amount of sXFI;
        // for every returned sXFI he receives ETH;
        // inverstors are left with nothing, he keeps the profit from selling tokens;
        // he must return everything to the system to get his ETH back;
        // anyway he wins, it's in his interest to get the money back;
        // even if it's almost margin call, he still wins and takes profit;

        // Tokens are de-activated on deal close (in Scenario 2)
    }

    native fun mint_sxfi(amount: u128): Dfinance::T<SXFI>;
}
}
