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
    const ERR_OFFER_INACTIVE: u64 = 101;
    const ERR_CANT_WITHDRAW: u64 = 100;

    // deal statuses
    const STATUS_DEAL_OKAY: u8 = 1;
    const STATUS_SOFT_MC_REACHED: u8 = 2;
    const STATUS_HARD_MC_REACHED: u8 = 3;

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
        min_ltv: u64,
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

    /// Get lender and deal_id from CDPSecurity.
    /// ```
    /// let sec = ...; // get security somehow
    /// let cdp = Security::borrow(sec);
    /// let (lender, deal_id) = CDP::read_security(cdp);
    /// ```
    public fun read_security<Offered: copyable, Collateral: copyable>(
        cdp: &CDPSecurity<Offered, Collateral>
    ): (address, u64) {
        (
            cdp.lender,
            cdp.deal_id
        )
    }

    /// Check whether <address> has an offer
    public fun has_offer<Offered: copyable, Collateral: copyable>(lender: address): bool {
        exists<Offer<Offered, Collateral>>(lender)
    }

    /// Read details from existing offer: min ltv, interest_rate and is_active
    public fun get_offer_details<Offered: copyable, Collateral: copyable>(
        lender: address
    ): (u64, u64, bool) acquires Offer {
        let off = borrow_global<Offer<Offered, Collateral>>(lender);

        (
            off.min_ltv,
            off.interest_rate,
            off.is_active
        )
    }

    /// Create an Offer by depositing some amount of Offered currency.
    /// After that anyone can make a deal in given currency pair and put his
    /// Collateral for Offered.
    public fun create_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        to_deposit: Dfinance::T<Offered>,
        min_ltv: u64,
        interest_rate: u64
    ) {
        assert(min_ltv <= MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Collateral, Offered>(), ERR_NO_ORACLE_PRICE);

        let deposit_amt = Dfinance::value(&to_deposit);

        move_to(account, Offer<Offered, Collateral> {
            deposit: to_deposit,
            collateral: Dfinance::zero<Collateral>(),
            proofs: Vector::empty<Security::Proof>(),
            deals: Vector::empty<Deal<Offered, Collateral>>(),
            deals_made: 0,
            is_active: true,
            min_ltv,
            interest_rate,
        });

        Event::emit(account, OfferCreatedEvent<Offered, Collateral> {
            lender: Signer::address_of(account),
            deposit_amt,
            min_ltv,
            interest_rate,
        });
    }

    /// Turn Offer into inactive status
    public fun deactivate_offer<Offered: copyable, Collateral: copyable>(
        account: &signer
    ) acquires Offer {
        let lender = Signer::address_of(account);
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        offer.is_active = false;
    }

    /// Activate Offer
    public fun activate_offer<Offered: copyable, Collateral: copyable>(
        account: &signer
    ) acquires Offer {
        let lender = Signer::address_of(account);
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        offer.is_active = true;
    }

    /// Deposit additional assets into the Offer.
    /// Anyone can deposit to any Offer except that he won't get anything
    /// in return for his investment.
    public fun deposit_to_offer<Offered: copyable, Collateral: copyable>(
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

    /// Withdraw some amount from Offer, only owner can do it
    public fun withdraw<Offered: copyable, Collateral: copyable>(
        account: &signer,
        withdraw_amt: u128
    ): Dfinance::T<Offered> acquires Offer {
        let lender = Signer::address_of(account);
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        assert(withdraw_amt < Dfinance::value(&offer.deposit), ERR_CANT_WITHDRAW);

        Dfinance::withdraw(&mut offer.deposit, withdraw_amt)
    }

    /// Withdraw whole deposit from Offer, only owner can do it
    public fun withdraw_all<Offered: copyable, Collateral: copyable>(
        account: &signer,
    ): Dfinance::T<Offered> acquires Offer {
        let lender = Signer::address_of(account);
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let amt    = Dfinance::value(&offer.deposit);

        Dfinance::withdraw(&mut offer.deposit, amt)
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
        let price = num(Coins::get_price<Collateral, Offered>(), EXCHANGE_RATE_DECIMALS);

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(amount_wanted, offered_decimals);

        let collateral_amt = Dfinance::value<Collateral>(&collateral);

        // MAX_OFFER_AMOUNT = COLLATERAL * EXCHANGE_RATE
        // - how much of Offered tokens could one get at max
        let max_offer_amount = Math::mul(num(collateral_amt, Dfinance::decimals<Collateral>()), price);

        // LTV = DESIRED_OFFERED_COINS / COLLATERAL * EXCHANGE_RATE
        // - what is actual LTV for this deal
        let ltv_unscaled = Math::div(copy offered_num, max_offer_amount);
        let ltv = (Math::scale_to_decimals(ltv_unscaled, LTV_DECIMALS) as u64);

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let min_ltv = offer.min_ltv;
        let interest_rate = offer.interest_rate;

        assert(offer.is_active, ERR_OFFER_INACTIVE);
        assert(ltv >= min_ltv && ltv <= MAX_LTV, ERR_INCORRECT_LTV); // Offer LTV = MIN LTV

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

    ///
    public fun get_deal_status_by_id<Offered: copyable, Collateral: copyable>(
        lender: address,
        deal_id: u64
    ): u8 acquires Offer {
        let offer     = borrow_global<Offer<Offered, Collateral>>(lender);
        let (deal, _) = find_deal<Offered, Collateral>(&offer.deals, deal_id);

        get_deal_status<Offered, Collateral>(deal)
    }

    /// Get status of the dealio - whether it has reached soft/hard MC or not
    public fun get_deal_status<Offered: copyable, Collateral: copyable>(
        deal: &Deal<Offered, Collateral>
    ): u8 {
        let price = Coins::get_price<Collateral, Offered>();

        if (price <= deal.hard_mc) {
            STATUS_HARD_MC_REACHED
        } else if (price <= deal.soft_mc) {
            STATUS_SOFT_MC_REACHED
        } else {
            STATUS_DEAL_OKAY
        }
    }

    /// Close the deal by margin call. Can be called by anyone, deal_id is
    /// currently required for closing.
    public fun close_by_margin_call<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        deal_id: u64
    ) acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let (deal_ref, pos) = find_deal(&offer.deals, deal_id);

        let status = get_deal_status(deal_ref);

        assert(status == STATUS_HARD_MC_REACHED, ERR_HARD_MC_HAS_NOT_OCCURRED);

        // Offered / Collateral is below the price of collateral profitability
        // let price = Coins::get_price<Collateral, Offered>();
        // assert(price <= hard_mc, ERR_HARD_MC_HAS_NOT_OCCURRED);

        // Margin call check - Okay; now we can remove the deal from the list

        let Deal {
            id: _,
            soft_mc,
            hard_mc,
            created_at: _,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt,
        } = Vector::remove(&mut offer.deals, pos);

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
        let (deal_ref, pos) = find_deal(&offer.deals, deal_id);

        let status = get_deal_status<Offered, Collateral>(deal_ref);

        assert(status != STATUS_HARD_MC_REACHED, ERR_HARD_MC_HAS_OCCURRED);

        // let price = Coins::get_price<Collateral, Offered>();
        // assert(price > hard_mc, ERR_HARD_MC_HAS_OCCURRED);

        let Deal {
            id: _,
            soft_mc: _,
            hard_mc: _,
            created_at,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt
        } = Vector::remove(&mut offer.deals, pos);

        let offered_num = num(offered_amt, Dfinance::decimals<Offered>());

        // Interest rate calculations

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

    /// Find deal with given ID in the list of deals and
    /// return the Deal and it's index in Offer.deals to be removed later
    fun find_deal<Offered: copyable, Collateral: copyable>(
        deals: &vector<Deal<Offered, Collateral>>,
        deal_id: u64
    ): (&Deal<Offered, Collateral>, u64) {
        let i = 0;
        let l = Vector::length(deals);

        while (i < l) {
            let deal = Vector::borrow<Deal<Offered, Collateral>>(deals, i);
            if (deal.id == deal_id) {
                return (deal, i)  // Vector::remove<Deal<Offered, Collateral>>(deals, i)
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
        min_ltv: u64,
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


