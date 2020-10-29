address 0x1 {
/// Every deal has two generic params:
///
/// - Offered - the offered currency which user would get in
/// exchange for Collateral
///
/// - Collateral - currency to put into deal which will not be
/// accessible until Offered is returned
module CDP {
    use 0x1::Coins;
    use 0x1::Dfinance;
    use 0x1::Security::{Self, Security};
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Vector;
    use 0x1::Event;
    use 0x1::Time;
    use 0x1::Math::{Self, num, num_unpack};

    const MAX_LTV: u64 = 6600;  // 66.00%
    const SOFT_MARGIN_CALL: u128 = 150;
    const HARD_MARGIN_CALL: u128 = 130;
    const SECONDS_IN_DAY: u128 = 86400;
    const EXCHANGE_RATE_DECIMALS: u8 = 8;
    const LTV_DECIMALS: u8 = 4;
    const LTV_100_PERCENT: u64 = 10000;
    const INTEREST_RATE_DECIMALS: u8 = 4;
    // 10^18
    const MAX_ACCURACY_DIVISION_MULTIPLIER: u128 = 1000000000000000000;

    const ERR_INCORRECT_LTV: u64 = 1;
    const ERR_NO_ORACLE_PRICE: u64 = 2;
    const ERR_HARD_MC_HAS_OCCURRED: u64 = 3;
    const ERR_HARD_MC_HAS_NOT_OCCURRED: u64 = 31;
    const ERR_DEAL_DOES_NOT_EXIST: u64 = 10;
    const ERR_SECURITY_DOES_NOT_EXIST: u64 = 11;

    resource struct Offer<Offered: copyable, Collateral: copyable> {
        deposit: Dfinance::T<Offered>,
        collateral: Dfinance::T<Collateral>,
        proofs: vector<Security::Proof>,
        // ID COUNTER
        deals_made: u64,
        deals: vector<Deal<Offered, Collateral>>,
        // whether Offer is available for deals
        is_active: bool,

        // < 6700, 2 signs after comma
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
    }

    struct Deal<Offered: copyable, Collateral: copyable> {
        id: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
        created_at: u64,
        interest_rate: u64,
        offered_amt: u128,
        collateral_amt: u128,
    }

    /// Marker for Security to use in `For` generic
    struct CDPSecurity<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64
    }


    public fun has_offer<Offered: copyable, Collateral: copyable>(lender: address): bool {
        exists<Offer<Offered, Collateral>>(lender)
    }

    /// Create an Offer by depositing some amount of Offered currency.
    /// After that anyone can make a deal in given currency pair and put his
    /// Collateral for Offered.
    public fun create_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        to_deposit: Dfinance::T<Offered>,
        ltv: u64,
        interest_rate: u64
    ) {
        assert(ltv <= MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);

        let deposit_amt = Dfinance::value(&to_deposit);

        move_to(account, Offer<Offered, Collateral> {
            deposit: to_deposit,
            collateral: Dfinance::zero<Collateral>(),
            proofs: Vector::empty<Security::Proof>(),
            deals: Vector::empty<Deal<Offered, Collateral>>(),
            deals_made: 0,
            is_active: true,
            ltv,
            interest_rate,
        });

        Event::emit(account, OfferCreatedEvent<Offered, Collateral> {
            lender: Signer::address_of(account),
            deposit_amt,
            ltv,
            interest_rate,
        });
    }

    /// Deposit additional assets into the Offer.
    /// Anyone can deposit to any Offer except that he won't get anything
    /// in return for his investment.
    public fun deposit_amount_to_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        to_deposit: Dfinance::T<Offered>
    ) acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let deposit_amt = Dfinance::value(&to_deposit);

        Dfinance::deposit<Offered>(&mut offer.deposit, to_deposit);

        Event::emit(account, OfferDepositedEvent<Offered, Collateral> {
            deposit_amt,
            lender,
        });
    }

    /// TBD
    /// Make deal with existing Offer (or Bank). Ask for some amount
    /// of Offered currency. If LTV for this amount/collateral is less
    /// than MIN and MAX LTV settings, deal will be make
    public fun make_cdp_deal<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        collateral: Dfinance::T<Collateral>,
        amount_wanted: u128,
    ): (Dfinance::T<Offered>, Security<CDPSecurity<Offered, Collateral>>) acquires Offer {
        let exchange_rate = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(amount_wanted, offered_decimals);

        let collateral_amt = Dfinance::value<Collateral>(&collateral);

        // MAX_OFFER_AMOUNT = COLLATERAL * EXCHANGE_RATE
        // - how much of Offered tokens could one get at max
        let max_offer_amount = Math::mul(num(collateral_amt, Dfinance::decimals<Collateral>()), exchange_rate);

        // LTV = DESIRED_OFFERED_COINS / COLLATERAL * EXCHANGE_RATE
        // - what is actual LTV for this deal
        let ltv_unscaled = Math::div(copy offered_num, max_offer_amount);
        let ltv = (Math::scale_to_decimals(ltv_unscaled, LTV_DECIMALS) as u64);

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let offer_ltv = offer.ltv;
        let interest_rate = offer.interest_rate;
        assert(ltv < offer_ltv, ERR_INCORRECT_LTV);

        let offered = Dfinance::withdraw<Offered>(&mut offer.deposit, amount_wanted);

        let (soft_mc, hard_mc) = compute_margin_calls(offered_num);

        let deal_id = offer.deals_made;
        // Issue Security for this deal which will hold the deal params in it
        let (security, proof) = Security::issue<CDPSecurity<Offered, Collateral>>(
            account,
            CDPSecurity {
                lender,
                deal_id,
            });

        let created_at = Time::now();
        let deal = Deal<Offered, Collateral> {
            soft_mc,
            hard_mc,
            created_at,
            offered_amt: amount_wanted,
            collateral_amt,
            id: deal_id,
            ltv,
            interest_rate,
        };
        // Update the bank with proof and collateral
        Vector::push_back(&mut offer.deals, deal);
        Vector::push_back(&mut offer.proofs, proof);
        Dfinance::deposit(&mut offer.collateral, collateral);
        offer.deals_made = deal_id + 1;

        Event::emit(account, DealCreatedEvent<Offered, Collateral> {
            lender,
            deal_id,
            soft_mc,
            hard_mc,
            created_at,
            collateral_amt,
            offered_amt: amount_wanted,
            borrower: Signer::address_of(account),
            ltv,
            interest_rate,
        });

        (offered, security)
    }

    /// Close the deal by margin call. Can be called by anyone, deal_id is
    /// currently required for closing.
    public fun close_by_margin_call<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        deal_id: u64
    ) acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let Deal {
            id: _,
            soft_mc,
            hard_mc,
            created_at: _,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt
        } = take_deal(&mut offer.deals, deal_id);

        let price = Coins::get_price<Offered, Collateral>();

        // Offered / Collateral is below the price of collateral profitability
        assert(price <= hard_mc, ERR_HARD_MC_HAS_NOT_OCCURRED);

        // If Hard MC is reached, then we can destroy the deal
        let collateral = Dfinance::withdraw(&mut offer.collateral, collateral_amt);

        // Give Collateral to the lender
        Account::deposit<Collateral>(account, lender, collateral);

        Event::emit(account, DealClosedOnMarginCallEvent<Offered, Collateral> {
            lender,
            deal_id,
            collateral_amt: collateral_amt,
            offered_amt: offered_amt,
            closed_at: Time::now(),
            soft_mc,
            hard_mc,
            ltv,
            interest_rate,
        });
    }

    /// Return Offered asset back (by passing Security)
    /// Required amount of money will be automatically taken from account.
    /// Collateral is returned on success.
    public fun pay_back<Offered: copyable, Collateral: copyable>(
        account: &signer,
        security: Security<CDPSecurity<Offered, Collateral>>,
    ): Dfinance::T<Collateral> acquires Offer {
        let lender = Security::borrow(&security).lender;

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let CDPSecurity { lender: _, deal_id } = resolve_security(&mut offer.proofs, security);

        let Deal {
            id: _,
            soft_mc: _,
            hard_mc,
            created_at,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt
        } = take_deal(&mut offer.deals, deal_id);
        let offered_num = num(offered_amt, Dfinance::decimals<Offered>());

        // Offered is above the price at which collateral is no longer profitable
        let price = Coins::get_price<Offered, Collateral>();
        assert(price > hard_mc, ERR_HARD_MC_HAS_OCCURRED);

        // Now we can proceed to interest rate calculations

        // min days since CDP created is 1
        let days_past = Time::days_from(created_at);
        let days_past = if (days_past != 0) days_past else 1;

        // DAYS_HELD_MULTIPLIER = NUM_DAYS_CDP_HELD / 365
        let days_held_multiplier = Math::div(
            // max accuracy is 18 decimals
            num((days_past as u128) * MAX_ACCURACY_DIVISION_MULTIPLIER, 18),
            num(365, 0)
        );
        let interest_rate_num = num((interest_rate as u128), INTEREST_RATE_DECIMALS);

        // OFFERED_COINS_OWNED =
        //      OFFERED_COINS_INITIALLY_RECEIVED
        //      + ( OFFERED_COINS_INITIALLY_RECEIVED * INTEREST_RATE_IN_YEAR * DAYS_HELD_MULTIPLIER )
        let pay_back_num = Math::add(
            copy offered_num,
            Math::mul(
                Math::mul(offered_num, interest_rate_num),
                days_held_multiplier
            )
        );
        let (pay_back_amt, _) = num_unpack(pay_back_num);

        // Return money by making a direct trasfer
        Account::pay_from_sender<Offered>(account, lender, pay_back_amt);

        let collateral = Dfinance::withdraw(&mut offer.collateral, collateral_amt);

        Event::emit(account, DealClosedOnBorrowerEvent<Offered, Collateral> {
            lender,
            pay_back_amt,
            collateral_amt: collateral_amt,
            borrower: Signer::address_of(account),
            ltv,
            interest_rate,
        });

        (collateral)
    }

    /// Take deal from list or fail if didn't find the seached asset
    fun take_deal<Offered: copyable, Collateral: copyable>(
        deals: &mut vector<Deal<Offered, Collateral>>,
        deal_id: u64
    ): Deal<Offered, Collateral> {
        let i = 0;
        let l = Vector::length(deals);
        while (i < l) {
            let deal = Vector::borrow<Deal<Offered, Collateral>>(deals, i);
            if (deal.id == deal_id) {
                return Vector::remove<Deal<Offered, Collateral>>(deals, i)
            };
            i = i + 1;
        };
        abort ERR_DEAL_DOES_NOT_EXIST
    }

    /// Walk through vector of Proofs to find match
    fun resolve_security<Offered: copyable, Collateral: copyable>(
        proofs: &mut vector<Security::Proof>,
        security: Security<CDPSecurity<Offered, Collateral>>
    ): CDPSecurity<Offered, Collateral> {
        let i = 0;
        let l = Vector::length(proofs);
        while (i < l) {
            let proof = Vector::borrow<Security::Proof>(proofs, i);
            if (Security::can_prove(&security, proof)) {
                return Security::prove(security, Vector::remove<Security::Proof>(proofs, i))
            };
            i = i + 1;
        };
        abort ERR_SECURITY_DOES_NOT_EXIST
    }

    fun compute_margin_calls(amount_wanted: Math::Num): (u128, u128) {
        // SMC = OFFERED_COINS * 1.3
        let soft_mc_multiplier = num(SOFT_MARGIN_CALL, 2);
        let soft_mc_num = Math::mul(copy amount_wanted, soft_mc_multiplier);

        // HMC = OFFERED_COINS * 1.5
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        let hard_mc_num = Math::mul(amount_wanted, hard_mc_multiplier);

        let soft_mc = Math::scale_to_decimals(soft_mc_num, EXCHANGE_RATE_DECIMALS);
        let hard_mc = Math::scale_to_decimals(hard_mc_num, EXCHANGE_RATE_DECIMALS);
        (soft_mc, hard_mc)
    }

    struct OfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        deposit_amt: u128,
        lender: address,
        ltv: u64,
        interest_rate: u64,
    }

    struct OfferDepositedEvent<Offered: copyable, Collateral: copyable> {
        deposit_amt: u128,
        lender: address,
    }

    struct OfferDepositBorrowedEvent<Offered: copyable, Collateral: copyable> {
        deposit_amt: u128,
        lender: address,
    }

    struct DealCreatedEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64,
        borrower: address,
        offered_amt: u128,
        collateral_amt: u128,
        created_at: u64,
        soft_mc: u128,
        hard_mc: u128,

        ltv: u64,
        interest_rate: u64,
    }

    struct DealClosedOnBorrowerEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        pay_back_amt: u128,
        collateral_amt: u128,

        ltv: u64,
        interest_rate: u64,
    }

    struct DealClosedOnMarginCallEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64,
        collateral_amt: u128,
        offered_amt: u128,
        closed_at: u64,
        soft_mc: u128,
        hard_mc: u128,

        ltv: u64,
        interest_rate: u64,
    }
}
}


