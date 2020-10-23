// ETH     = 1000000000000000000 (18 decimal places) 1.0
// BTC     = 100000000           (8 decimal places)  1.0
// ETH_BTC = 20000000            (8 decimal places)  0.2
//
// 100 Sat = 0.000001 = 100 BTC in Dfinance
// ETH * ETH_BTC / 10^8 = Error 10^10
//
// SUM(A(VALUE, DEC), B(VALUE, DEC))
// MUL(A(VALUE, DEC), B(VALUE, DEC))
// MAX(A(VALUE, DEC), B(VALUE, DEC))
//
// POW(VALUE, POWER)
//
//
// 1 = 0.00000000000000001 ETH
// 100 = 0.0000000000001 ETH
// 1000 = 0.00000000001 ETH


address 0xDF1 {
module SXFIMintProxy {

//    use 0x1::CDS;

    const ERR_NO_PERMISSION : u64 = 1001;

//    public fun grant_permission(account: &signer) {
//        if (CDS::has_mint_permission(account)) {
//
//        } else {
//            abort 1000
//        };
//    }

    fun mint() {

    }

    native fun create_signer(addr: address): signer;
    native fun destroy_signer(acc: signer);
}
}

address 0x1 {


// 1. sXFI must be present in Oracle module Oracle::get_price<sXFI, ETH> - learn how
// 2. Discuss sXFI status. How can one get it if not from CDS dealio?

module SXFI {
    struct T {}
}


/// TOKEN CAN HAVE EXPIRATION DATE!!!!!
/// WOW.

/// ONLY ONE TOKEN FOR THIS COLLATERAL!!!!!
/// EXCHANGE TOKEN. CAN BE CALLED COUPON.
/// MADE FOR RB (INVESTOR) FOR EASIER.
/// CALCULATION OF PROFITS.

/// 

/// Swaption
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
    resource struct T<Collateral, Token: copyable> {
        locked: Dfinance::T<Collateral>,
        token_amount: u128,
        margin_call: u8,
        // set timestamp for deal end
    }

    public fun create<Collateral, Token: copyable>(
        account: &signer,
        // collateral: Dfinance::T<Collateral>
    ) {

        // assert(Dfinance::value(&collateral) != 0, ERR_NO_COLLATERAL);

        let total_supply = 100;

        let _ = Signer::address_of(account);
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

        // premium - money USER makes for selling TOKENs
        // user    - the guy who locks his COLLATERAL (A) in exchange for X * A = B SXFI; (X < 1)

        // Scenario 1. - Margin Call - USER lost, SYSTEM and INVESTORS win
        //
        // if deal is closed by margin call;
        // 0x1 locks the dealio;
        // his ETH is divided by token holders;
        // he keeps the premium and sXFI;
        // token holders can exchange their tokens for collateral value;
        //
        // investor buys an option (token) to buy collateral for smaller percent;
        // commission percent is decided globally by system;

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

    /// TODO: find a way to do something about this function. Maybe replace it
    ///       with anything else, maybe there's a solution out there waiting for us
    native fun mint_sxfi(amount: u128): Dfinance::T<SXFI>;
}
}
