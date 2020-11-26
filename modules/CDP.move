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
    use 0x1::Math::{Self, num};

    const MAX_LTV: u64 = 6600;  // 66.00%
    const SOFT_MARGIN_CALL: u128 = 150;
    const HARD_MARGIN_CALL: u128 = 130;
    const EXCHANGE_RATE_DECIMALS: u8 = 8;
    const LTV_100_PERCENT: u64 = 10000;

    const LTV_DECIMALS: u8 = 2;
    const INTEREST_RATE_DECIMALS: u8 = 4;

    // 10^18
    const MAX_ACCURACY_DIVISION_MULTIPLIER: u128 = 1000000000000000000;

    // offer creation constants start with 100
    const ERR_INCORRECT_LTV: u64 = 101;
    const ERR_NO_ORACLE_PRICE: u64 = 102;
    const ERR_ZERO_DRO_GATE: u64 = 103;
    const ERR_OFFER_DOES_NOT_EXIST: u64 = 104;

    // deal close params
    const ERR_HARD_MC_HAS_OCCURRED: u64 = 301;
    const ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED: u64 = 302;
    const ERR_DEAL_DOES_NOT_EXIST: u64 = 303;
    const ERR_NOT_ENOUGH_MONEY: u64 = 304;
    const ERR_DEAL_NOT_EXPIRED: u64 = 305;

    // dro related
    const ERR_DRO_NOT_ALLOWED: u64 = 401;
    const ERR_DRO_ALREADY_ISSUED: u64 = 402;
    const ERR_DRO_TOO_LONG: u64 = 403;
    const ERR_DRO_TOO_EARLY: u64 = 404;
    const ERR_DRO_SOFT_MC_NOT_REACHED: u64 = 405;

    const ERR_ZERO_AMOUNT: u64 = 201;

    const ERR_SECURITY_DOES_NOT_EXIST: u64 = 11;
    const ERR_OFFER_INACTIVE: u64 = 201;
    const ERR_CANT_WITHDRAW: u64 = 200;

    // deal statuses
    const STATUS_DEAL_OKAY: u8 = 1;
    const STATUS_SOFT_MC_REACHED: u8 = 2;
    const STATUS_HARD_MC_REACHED: u8 = 3;
    const STATUS_EXPIRED: u8 = 4;

    const REASON_MC: u8 = 1;
    const REASON_TIME: u8 = 2;

    resource struct Offer<Offered: copyable, Collateral: copyable> {
        deposit: Dfinance::T<Offered>,
        collateral: Dfinance::T<Collateral>,
        proofs: vector<Security::Proof>,
        // ID COUNTER
        deals_made: u64,
        deals: vector<Deal<Offered, Collateral>>,
        deal_duration: u64,
        // whether Offer is available for deals
        is_active: bool,

        // < 6700, 2 signs after comma
        min_ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
        // whether to allow issuing new coins
        allow_dro: bool,

        // how much time DRO owner has until deal can be
        // liquidated by lender
        dro_buy_gate: u64,
    }

    struct Deal<Offered: copyable, Collateral: copyable> {
        id: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
        allow_dro: bool,
        dro_issued: bool,
        ends_at: u64,
        dro_buy_gate: u64,
        created_at: u64,
        interest_rate: u64,
        offered_amt: u128,
        collateral_amt: u128,
    }

    /// Marker for CDP Security to use in `For` generic
    struct CDP<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64
    }

    /// Marker for DRO Security to use in `For` generic
    struct DRO<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64
    }

    /// Get lender and deal_id from CDP.
    /// ```
    /// let sec = ...; // get security somehow
    /// let cdp = Security::borrow(sec);
    /// let (lender, deal_id) = CDP::read_security(cdp);
    /// ```
    public fun read_security<Offered: copyable, Collateral: copyable>(
        cdp: &CDP<Offered, Collateral>
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

    /// Read details from existing offer:
    /// - deposit amount
    /// - min ltv,
    /// - interest_rate
    /// - is_active
    /// - allow_dro
    /// - dro_buy_gate (is allowed)
    public fun get_offer_details<Offered: copyable, Collateral: copyable>(
        lender: address
    ): (u128, u64, u64, bool, bool, u64) acquires Offer {
        let off = borrow_global<Offer<Offered, Collateral>>(lender);

        (
            Dfinance::value(&off.deposit),
            off.min_ltv,
            off.interest_rate,
            off.is_active,
            off.allow_dro,
            off.dro_buy_gate
        )
    }

    /// Create an Offer disallowing DRO
    public fun create_offer_without_dro<Offered: copyable, Collateral: copyable>(
        account: &signer,
        to_deposit: Dfinance::T<Offered>,
        min_ltv: u64,
        interest_rate: u64,
        deal_duration: u64
    ) {
        create_offer<Offered, Collateral>(
            account,
            to_deposit,
            min_ltv,
            interest_rate,
            deal_duration,
            false,
            0
        )
    }

    /// Create an Offer by depositing some amount of Offered currency.
    /// After that anyone can make a deal in given currency pair and put his
    /// Collateral for Offered.
    public fun create_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        to_deposit: Dfinance::T<Offered>,
        min_ltv: u64,
        interest_rate: u64,
        deal_duration: u64,
        allow_dro: bool,
        dro_buy_gate: u64,
    ) {
        assert(min_ltv < MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Collateral, Offered>(), ERR_NO_ORACLE_PRICE);
        assert(allow_dro == false || dro_buy_gate > 0, ERR_ZERO_DRO_GATE);

        let deposit_amt = Dfinance::value(&to_deposit);

        move_to(account, Offer<Offered, Collateral> {
            deposit: to_deposit,
            collateral: Dfinance::zero<Collateral>(),
            proofs: Vector::empty<Security::Proof>(),
            deals: Vector::empty<Deal<Offered, Collateral>>(),
            deals_made: 0,
            is_active: true,
            min_ltv,
            allow_dro,
            interest_rate,
            deal_duration,
            dro_buy_gate
        });

        Event::emit(account, OfferCreatedEvent<Offered, Collateral> {
            lender: Signer::address_of(account),
            deposit_amt,
            min_ltv,
            interest_rate,
            allow_dro,
            deal_duration,
            dro_buy_gate
        });
    }

    /// Turn Offer into inactive status
    public fun deactivate_offer<Offered: copyable, Collateral: copyable>(
        account: &signer
    ) acquires Offer {
        let lender = Signer::address_of(account);
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        offer.is_active = false;

        Event::emit(account, OfferDeactivatedEvent<Offered, Collateral> {
            lender
        });
    }

    /// Activate Offer
    public fun activate_offer<Offered: copyable, Collateral: copyable>(
        account: &signer
    ) acquires Offer {
        let lender = Signer::address_of(account);
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        offer.is_active = true;

        Event::emit(account, OfferActivatedEvent<Offered, Collateral> {
            lender
        });
    }

    /// Deposit additional assets into the Offer.
    /// Anyone can deposit to any Offer except that he won't get anything
    /// in return for his investment.
    public fun deposit<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        to_deposit: Dfinance::T<Offered>
    ) acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
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
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        assert(withdraw_amt <= Dfinance::value(&offer.deposit), ERR_CANT_WITHDRAW);

        Event::emit(account, OfferWithdrawalEvent<Offered, Collateral> {
            withdraw_amt,
            lender
        });

        Dfinance::withdraw(&mut offer.deposit, withdraw_amt)
    }

    /// Withdraw whole deposit from Offer, only owner can do it
    public fun withdraw_all<Offered: copyable, Collateral: copyable>(
        account: &signer,
    ): Dfinance::T<Offered> acquires Offer {
        let lender = Signer::address_of(account);
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        let withdraw_amt = Dfinance::value(&offer.deposit);

        Event::emit(account, OfferWithdrawalEvent<Offered, Collateral> {
            withdraw_amt,
            lender
        });

        Dfinance::withdraw(&mut offer.deposit, withdraw_amt)
    }

    /// Make deal with existing Offer (or Bank). Ask for some amount
    /// of Offered currency. If LTV for this amount/collateral is less
    /// than MIN and MAX LTV settings, deal will be make
    public fun make_deal<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        collateral: Dfinance::T<Collateral>,
        amount_wanted: u128,
    ): (Dfinance::T<Offered>, Security<CDP<Offered, Collateral>>) acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );

        let price = num(Coins::get_price<Collateral, Offered>(), EXCHANGE_RATE_DECIMALS);

        let offered_dec    = Dfinance::decimals<Offered>();
        let collateral_dec = Dfinance::decimals<Collateral>();
        let collateral_amt = Dfinance::value(&collateral);

        assert(amount_wanted > 0, ERR_ZERO_AMOUNT);
        assert(collateral_amt > 0, ERR_ZERO_AMOUNT);

        // MAX OFFER in Offered (1to1) = COLL_AMT * COLL_OFF_PRICE;
        let max_offer = {
            let coll    = num(collateral_amt, collateral_dec);
            let max_off = Math::mul(coll, copy price);

            max_off
        };

        let wanted_num = num(amount_wanted, offered_dec);

        // LTV = WANTED / MAX * 100; 2 decimals
        let ltv = {
            let ltv_perc = Math::div(copy wanted_num, max_offer);
            let ltv_perc = Math::scale_to_decimals(ltv_perc, 2);

            ((ltv_perc * 100) as u64)
        };

        let (soft_mc, hard_mc) = compute_margin_calls(wanted_num);

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let min_ltv = offer.min_ltv;
        let interest_rate = offer.interest_rate;

        assert(offer.is_active, ERR_OFFER_INACTIVE);
        assert(ltv >= min_ltv && ltv <= MAX_LTV, ERR_INCORRECT_LTV); // Offer LTV = MIN LTV

        let offered = Dfinance::withdraw<Offered>(&mut offer.deposit, amount_wanted);
        let deal_id = offer.deals_made;

        let created_at = Time::now();
        let ends_at = created_at + offer.deal_duration;

        // Issue Security for this deal which will hold the deal params in it
        let (security, proof) = Security::issue<CDP<Offered, Collateral>>(
            account,
            CDP { lender, deal_id },
            ends_at + offer.dro_buy_gate // just in case, if there's a buy off gate in DRO scenario
        );

        let deal = Deal<Offered, Collateral> {
            soft_mc,
            hard_mc,
            ends_at,
            created_at,
            allow_dro: offer.allow_dro,
            dro_buy_gate: offer.dro_buy_gate,
            offered_amt: amount_wanted,
            dro_issued: false,
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
            ends_at,
            collateral_amt,
            offered_amt: amount_wanted,
            borrower: Signer::address_of(account),
            ltv,
            interest_rate,
        });

        (offered, security)
    }


    public fun create_dro<Offered: copyable, Collateral: copyable>(
        account: &signer,
        security: &Security<CDP<Offered, Collateral>>,
        dro_time: u64 // TIME IN SECONDS
    ): Security<DRO<Offered, Collateral>> acquires Offer {

        let CDP {
            deal_id,
            lender
        } = *Security::borrow(security);

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let (deal_ref, pos) = find_deal<Offered, Collateral>(&offer.deals, deal_id);
        let dro_end = Time::now() + dro_time;

        assert(deal_ref.allow_dro, ERR_DRO_NOT_ALLOWED);
        assert(deal_ref.dro_issued == false, ERR_DRO_ALREADY_ISSUED);
        assert(deal_ref.ends_at >= dro_end, ERR_DRO_TOO_LONG);

        // If conditions are met we can issue DRO
        // TODO: maybe think of `find_deal_mut` method not to pull element from Vector
        let deal = Vector::remove(&mut offer.deals, pos);
        let dro_ends_at = dro_end + deal.dro_buy_gate;

        deal.dro_issued = true;
        deal.ends_at = dro_ends_at;

        let (dro, proof) = Security::issue<DRO<Offered, Collateral>>(
            account,
            DRO { lender, deal_id },
            dro_ends_at
        );

        // Put modified deal into storage
        Vector::push_back(&mut offer.deals, deal);
        Vector::push_back(&mut offer.proofs, proof); // DRO proof is just like any other proof

        // ADD Event::emit<DroCreated>( /* decide which params to add here */ );

        (dro)
    }

    ///
    public fun get_deal_status_by_id<Offered: copyable, Collateral: copyable>(
        lender: address,
        deal_id: u64
    ): u8 acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer     = borrow_global<Offer<Offered, Collateral>>(lender);
        let (deal, _) = find_deal<Offered, Collateral>(&offer.deals, deal_id);

        get_deal_status<Offered, Collateral>(deal)
    }

    /// Get status of the dealio - whether it has reached soft/hard MC or not
    fun get_deal_status<Offered: copyable, Collateral: copyable>(
        deal: &Deal<Offered, Collateral>
    ): u8 {
        let price = Coins::get_price<Collateral, Offered>();
        let now   = Time::now();

        if (now > deal.ends_at) {
            STATUS_EXPIRED
        } else if (price <= deal.hard_mc) {
            STATUS_HARD_MC_REACHED
        } else if (price <= deal.soft_mc) {
            STATUS_SOFT_MC_REACHED
        } else {
            STATUS_DEAL_OKAY
        }
    }

    /// Close the deal by margin call. Can be called by anyone, deal_id is
    /// currently required for closing.
    public fun close_by_status<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        deal_id: u64
    ) acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let (deal_ref, pos) = find_deal(&offer.deals, deal_id);
        let status = get_deal_status(deal_ref);

        assert(
            status == STATUS_HARD_MC_REACHED || status == STATUS_EXPIRED,
            ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED
        );

        let Deal {
            id: _,
            soft_mc,
            hard_mc,
            allow_dro: _,
            created_at: _,
            dro_buy_gate: _,
            ends_at: _,
            dro_issued: _,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt,
        } = Vector::remove(&mut offer.deals, pos);

        // If Hard MC is reached, then we can destroy the deal
        let collateral = Dfinance::withdraw(&mut offer.collateral, collateral_amt);

        // Give Collateral to the lender
        Account::deposit<Collateral>(account, lender, collateral);

        let reason = if (status == STATUS_EXPIRED) {
            REASON_TIME
        } else {
            REASON_MC
        };

        Event::emit(account, DealClosedByStatusEvent<Offered, Collateral> {
            lender,
            deal_id,
            collateral_amt: collateral_amt,
            offered_amt: offered_amt,
            closed_at: Time::now(),
            soft_mc,
            hard_mc,
            reason,
            ltv,
            interest_rate,
        });
    }

    /// Important
    /// If DRO resource exists - it automatically means that:
    /// 1. deal allows DRO
    /// 2. ends_at = dro_time + dro_buy_gate
    /// But DEAL MAY NOT EXIST AT THE TIME (was closed by different scenario)
    public fun pay_back_dro<Offered: copyable, Collateral: copyable>(
        account: &signer,
        security: Security<DRO<Offered, Collateral>>
    ): Dfinance::T<Collateral> acquires Offer {
        let DRO {
            lender,
            deal_id
        } = *Security::borrow(&security);

        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let (deal_ref, pos) = find_deal(&offer.deals, deal_id);
        let status = get_deal_status<Offered, Collateral>(deal_ref);

        let now = Time::now();
        let dro_end = deal_ref.ends_at - deal_ref.dro_buy_gate; // buy gate is not included

        assert(now >= dro_end, ERR_DRO_TOO_EARLY);
        assert(status == STATUS_SOFT_MC_REACHED, ERR_DRO_SOFT_MC_NOT_REACHED);

        // let stmt can be omitted
        let _ = resolve_security<DRO<Offered, Collateral>>(&mut offer.proofs, security);

        let Deal {
            id: _,
            allow_dro: _,
            dro_issued: _,
            soft_mc: _,
            hard_mc: _,
            ends_at: _,
            dro_buy_gate: _,
            created_at: _, // also
            ltv: _, // You'll need this
            interest_rate: _, // and this
            offered_amt,
            collateral_amt
        } = Vector::remove(&mut offer.deals, pos);

        // TODO: the Math, simply copy-paste from `pay_back` method
        // THIS DUDE MUST PAY OFFERED_AMT + INTEREST RATE BACK
        let pay_back_amt = offered_amt;

        assert(Account::balance<Offered>(account) >= pay_back_amt, ERR_NOT_ENOUGH_MONEY);

        // Return money by making a direct trasfer
        let offered_paid = Account::withdraw_from_sender(account, pay_back_amt);
        Dfinance::deposit<Offered>(&mut offer.deposit, offered_paid);

        let collateral = Dfinance::withdraw(&mut offer.collateral, collateral_amt);

        // MAKE IT DRO EVENT
        // Event::emit(account, DealClosedPayBackEvent<Offered, Collateral> {
        //     ltv,
        //     lender,
        //     deal_id,
        //     pay_back_amt,
        //     interest_rate,
        //     collateral_amt,
        //     borrower: Signer::address_of(account),
        // });

        (collateral)

    }

    /// Return Offered asset back (by passing Security)
    /// Required amount of money will be automatically taken from account.
    /// Collateral is returned on success.
    public fun pay_back<Offered: copyable, Collateral: copyable>(
        account: &signer,
        security: Security<CDP<Offered, Collateral>>,
    ): Dfinance::T<Collateral> acquires Offer {
        let lender = Security::borrow(&security).lender;
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let CDP { lender: _, deal_id } = resolve_security<CDP<Offered, Collateral>>(&mut offer.proofs, security);
        let (deal_ref, pos) = find_deal(&offer.deals, deal_id);
        let status = get_deal_status<Offered, Collateral>(deal_ref);

        assert(status != STATUS_HARD_MC_REACHED, ERR_HARD_MC_HAS_OCCURRED);

        let Deal {
            id: _,
            allow_dro: _,
            dro_issued: _,
            soft_mc: _,
            hard_mc: _,
            ends_at: _,
            dro_buy_gate: _,
            created_at,
            ltv,
            interest_rate,
            offered_amt,
            collateral_amt
        } = Vector::remove(&mut offer.deals, pos);

        // TODO:
        // forbid if:
        // 1. DRO was issued, DRO time has come and SOFT_MC REACHED
        // 2. DRO was issued, time has not come
        // allow if:
        // 1. no DRO
        // 2. HARD MC not reached

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(offered_amt, offered_decimals);

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

        // it's in 18th dimension after Math::mul, need to scale down to `offered_decimals`
        let pay_back_amt = Math::scale_to_decimals(pay_back_num, offered_decimals);

        assert(Account::balance<Offered>(account) >= pay_back_amt, ERR_NOT_ENOUGH_MONEY);

        // Return money by making a direct trasfer
        let offered_paid = Account::withdraw_from_sender(account, pay_back_amt);
        Dfinance::deposit<Offered>(&mut offer.deposit, offered_paid);

        let collateral = Dfinance::withdraw(&mut offer.collateral, collateral_amt);

        Event::emit(account, DealClosedPayBackEvent<Offered, Collateral> {
            ltv,
            lender,
            deal_id,
            pay_back_amt,
            interest_rate,
            collateral_amt,
            borrower: Signer::address_of(account),
        });

        (collateral)
    }

    public fun get_deal_details<Offered: copyable, Collateral: copyable>(
        lender: address,
        deal_id: u64
    ): (u64, u128, u128, u64, u64, u128, u128) acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(lender),
            ERR_OFFER_DOES_NOT_EXIST
        );
        let off  = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let (deal, _) = find_deal<Offered, Collateral>(&off.deals, deal_id);

        (
            deal.ltv,
            deal.soft_mc,
            deal.hard_mc,
            deal.created_at,
            deal.interest_rate,
            deal.offered_amt,
            deal.collateral_amt,
        )
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
    fun resolve_security<SecurityType: copyable>(
        proofs: &mut vector<Security::Proof>,
        security: Security<SecurityType>
    ): SecurityType {
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
        deal_duration: u64,
        allow_dro: bool,
        dro_buy_gate: u64
    }

    struct OfferDepositedEvent<Offered: copyable, Collateral: copyable> {
        deposit_amt: u128,
        lender: address,
    }

    struct OfferWithdrawalEvent<Offered: copyable, Collateral: copyable> {
        withdraw_amt: u128,
        lender: address,
    }

    struct DealCreatedEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64,
        borrower: address,
        offered_amt: u128,
        collateral_amt: u128,
        ends_at: u64,
        created_at: u64,
        soft_mc: u128,
        hard_mc: u128,

        ltv: u64,
        interest_rate: u64,
    }

    struct OfferDeactivatedEvent<Offered: copyable, Collateral: copyable> {
        lender: address
    }

    struct OfferActivatedEvent<Offered: copyable, Collateral: copyable> {
        lender: address
    }

    struct DealClosedPayBackEvent<Offered: copyable, Collateral: copyable> {
        deal_id: u64,
        lender: address,
        borrower: address,
        pay_back_amt: u128,
        collateral_amt: u128,

        ltv: u64,
        interest_rate: u64,
    }

    struct DealClosedByStatusEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64,
        collateral_amt: u128,
        offered_amt: u128,
        closed_at: u64,
        soft_mc: u128,
        hard_mc: u128,
        reason: u8,
        ltv: u64,
        interest_rate: u64,
    }
}
}


