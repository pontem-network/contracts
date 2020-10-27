address 0x1 {

/// Every deal has two generic params:
///
/// - Offered - the offered currency which user would get in
/// exchange for Collateral
///
/// - Collateral - currency to put into deal which will not be
/// accessible until Offered is returned
module CDP2 {
    use 0x1::Coins;
    use 0x1::Dfinance;
    use 0x1::Security::{Self, Security};
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Vector;
    use 0x1::Event;
    use 0x1::Time;
    use 0x1::Math::{Self, Num, num_create as num, num_unpack};

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

    struct DealParams {
        // < 6700, 2 signs after comma
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
    }

    resource struct Offer<Offered: copyable, Collateral: copyable> {
        deposit: Dfinance::T<Offered>,
        params: DealParams,

        collateral: Dfinance::T<Collateral>,
        proofs: vector<Security::Proof>,
        deals_made: u64, // ID COUNTER
        deals: vector<Deal>,

        is_active: bool  // whether Offer is available for deals
    }

    struct Deal<Offered: copyable, Collateral: copyable> {
        id: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
        created_at: u64,
        offered_amt: u128,
        collateral_amt: u128
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
        let params      = DealParams { ltv, interest_rate };

        move_to(account, Offer<Offered, Collateral> {
            deposit: to_deposit,
            params: copy params,
            is_active: true,
            collateral: Dfinance::zero<Collateral>(),
            proofs: Vector::empty<Security::Proof>(),
            deals_made: 0
        });

        Event::emit(account, OfferCreatedEvent<Offered, Collateral> {
            lender: Signer::address_of(account),
            deposit_amt,
            params,
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

        let offer       = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let deposit_amt = Dfinance::value(&to_deposit);

        Dfinance::deposit<Offered>(&mut offer.deposit, to_deposit);

        Event::emit(account, OfferDepositedEvent<Offered, Collateral> {
            deposit_amt,
            lender,
        });
    }

    struct CDP<Offered: copyable, Collateral: copyable> {
        lender: address,
        deal_id: u64
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
    ): (Dfinance::T<Offered>, Security<CDP<Offered, Collateral>>) acquires Offer {

        let offered_decimals = Dfinance::decimals<Offered>();
        let collateral_amt   = Dfinance::value<Collateral>(&collateral);
        let exchange_rate    = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let collateral_num   = num(collateral_value, Dfinance::decimals<Collateral>());
        let offered_num      = num(amount_wanted, offered_decimals);

        // MAX_OFFER_AMOUNT = COLLATERAL * EXCHANGE_RATE
        // - how much Offered could one get at max
        // LTV = DESIRED_OFFERED_COINS / COLLATERAL * EXCHANGE_RATE
        // - what is actual LTV for this deal
        let max_offer_amount = Math::mul(collateral_num, exchange_rate);
        let ltv_unscaled     = Math::div(offered_num, max_offer_amount);

        // add assert(LTV < SYSTEM_MAX_LTV);
        // add assert(LTV > DEAL_MIN_LTV)

        let ltv = (Math::scale_to_decimals(ltv_unscaled, LTV_DECIMALS) as u64);

        let offer         = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let offer_ltv     = offer.params.ltv;
        let interest_rate = offer.params.interest_rate;

        assert(ltv >= offer_ltv, ERR_INCORRECT_LTV); // OR ERR_LTV_TOO_SMALL

        let offered = Dfinance::withdraw<Offered>(&mut offer.deposit, amount_wanted);
        let (soft_mc, hard_mc) = compute_margin_calls(num(amount_wanted, offered_decimals));

        let created_at  = Time::now();
        let offered_amt = Dfinance::value(&offered);
        let borrower    = Signer::address_of(account);
        let deal_params = DealParams { interest_rate, ltv };

        // Issue Security for this deal which will hold the deal params in it
        let (security, proof) = Security::issue<CDP<Offered, Collateral>>(account, CDP {
            lender,
            deal_id: offer.deals_made,
        });

        let deal = Deal {
            ltv,
            soft_mc,
            hard_mc,
            created_at,
            offered_amt,
            collateral_amt,
            id: deal_id,
        };

        // Update the bank with proof and collateral
        Vector::push_back(&mut offer.deals, deal);
        Vector::push_back(&mut offer.proofs, proof);
        Dfinance::deposit(&mut offer.collateral, collateral);
        offer.deals_made = offer.deals_made + 1;

        Event::emit(account, DealCreatedEvent<Offered, Collateral> {
            lender,
            borrower,
            soft_mc,
            hard_mc,
            created_at,
            params: deal_params,
            offered: offered_value,
            collateral: collateral_value,
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
        let deal  = take_deal(&mut offer.deals, deal_id);

        let price = Coins::get_price<Offered, Collateral>();

        // Offered is above the price at which collateral is no longer profitable
        assert(price >= deal.hard_mc, ERR_HARD_MC_HAS_NOT_OCCURRED);

        // If Hard MC is reached, then we can destroy the dealio
        let collateral = Dfinance::withdraw(&mut offer.collateral, deal.collateral_amt);

        // Give Collateral to the lender
        Account::deposit<Collateral>(account, lender, collateral);

        Event::emit(account, DealClosedOnMarginCallEvent<Offered, Collateral> {
            lender,
            borrower,
            collateral: collateral_value_stored,
            collateral_in_offered: offered_for_collateral,
            closed_at: Time::now(),
            params,
            soft_mc,
            hard_mc,
        });
    }

    /// Return Offered asset back (by passing Security)
    /// Required amount of money will be automatically taken from account.
    /// Collateral is returned on success.
    public fun pay_back<Offered: copyable, Collateral: copyable>(
        account: &signer,
        security: Security<CDP<Offered, Collateral>>,
    ): Dfinance::T<Collateral> acquires Deal {

        let lender = Security::borrow(&security).lender;
        let offer  = borrow_global_mut<Offer<Offered, Collateral>>(params.lender);
        let params = destroy_security(&mut offer.proofs, security);
        let deal   = take_deal(&mut offer.deals, params.deal_id);
        let price  = Coins::get_price<Offered, Collateral>();

        // Offered is above the price at which collateral is no longer profitable
        assert(price < deal.hard_mc, ERR_HARD_MC_HAS_OCCURRED);

        // Now we can procceed to interest rate calculations

        // min days since CDP created is 1
        let days_past = Time::days_from(deal.created_at);
        let days_past = if (days_past != 0) days_past else 1;

        // DAYS_HELD_MULTIPLIER = NUM_DAYS_CDP_HELD / 365
        let ir_multiplier = Math::div(
            // max accuracy is 18 decimals
            num(days_past * MAX_ACCURACY_DIVISION_MULTIPLIER, 18),
            num(365, 0)
        );

        let offered_num       = num(deal.offered_amt, Dfinance::decimals<Offered>());
        let interest_rate_num = num((deal.interest_rate as u128), INTEREST_RATE_DECIMALS);

        // OFFERED_COINS_OWNED =
        //      OFFERED_COINS_INITIALLY_RECEIVED
        //      + ( OFFERED_COINS_INITIALLY_RECEIVED * INTEREST_RATE_IN_YEAR * DAYS_HELD_MULTIPLIER )
        let pay_back_amt_num = Math::add(
            copy offered_num,
            Math::mul(
                Math::mul(offered_num, interest_rate_num),
                ir_multiplier
            )
        );

        let (pay_back_amt, _) = num_unpack(pay_back_amt_num);

        // Return money by making a direct trasfer
        Account::pay_from_sender<Offered>(account, lender, pay_back_amt);

        let collateral = Dfinance::withdraw(&mut offer.collateral, deal.collateral_amt);

        Event::emit(account, DealClosedOnBorrowerEvent<Offered, Collateral> {
            lender,
            borrower,
            collateral: collateral_value_stored,
            collateral_in_offered: offered_for_collateral,
            params,
            soft_mc,
            hard_mc,
        });

        (collateral)
    }

    /// Take deal from list or fail if didn't find the seached asset
    fun take_deal<Off, Coll>(deals: &mut vector<Deal<Off, Coll>>, deal_id: u64): Deal {
        let i = 0;
        let l = Vector::length(deals);
        while (i < l) {
            let deal = Vector::borrow(deals, i);
            if (deal.id == deal_id) {
                return Vector::remove(deals, i);
            };
            i = i + 1;
        };

        // No deal at all!
        abort 10;
    }

    /// Walk through vector of Proofs to find match
    fun destroy_security<Off, Coll>(
        proofs: &mut vector<Proof>,
        sec: Security<CDPDeal<Off, Coll>>
    ): CDPDeal<Off, Coll> {
        let i = 0;
        let l = Vector::length(proofs);
        while (i < l) {
            let proof = Vector::borrow(proofs, i);

            if (Security::can_prove(&sec, &proof)) {
                return Security::prove(sec, Vector::remove(proofs, i));
            };

            i = i + 1;
        };

        abort 10;
    }

    fun compute_margin_calls(amount_wanted: Num): (u128, u128) {
        let soft_mc_multiplier = num(SOFT_MARGIN_CALL, 2);
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);

        // SMC = OFFERED_COINS * 1.3 ; HMC = OFFERED_COINS * 1.5
        let (soft_mc, _) = num_unpack(Math::mul(copy amount_wanted, soft_mc_multiplier));
        let (hard_mc, _) = num_unpack(Math::mul(amount_wanted, hard_mc_multiplier));

        (soft_mc, hard_mc)
    }

    fun compute_offered_value_for_collateral<Offered: copyable, Collateral: copyable>(collateral: u128, ltv: u64): Num {
        let exchange_rate = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let ltv_rate = num((ltv as u128), LTV_DECIMALS);
        let collateral = num(collateral, Dfinance::decimals<Collateral>());

        // OFFERED_COINS_AVAILABLE_IN_EXCHANGE_FOR_COLLATERAL =
        //     OFFERED_TO_COLLATERAL_EXCHANGE_RATE * COLLATERAL * LOAN_TO_VALUE_RATE
        let offered_unscaled = Math::mul(
            Math::mul(exchange_rate, collateral),
            ltv_rate
        );

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered = Math::scale_to_decimals(offered_unscaled, offered_decimals);

        num(offered, offered_decimals)
    }

    struct OfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        deposit_amt: u128,
        lender: address,
        params: DealParams,
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
        offered: u128,
        collateral: u128,
        created_at: u64,
        soft_mc: u128,
        hard_mc: u128,
        params: DealParams,
    }

    struct DealClosedOnBorrowerEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        collateral: u128,
        collateral_in_offered: u128,
        closed_at: u64,
        soft_mc: u128,
        hard_mc: u128,
        params: DealParams,
    }

    struct DealClosedOnMarginCallEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        collateral: u128,
        collateral_in_offered: u128,
        closed_at: u64,
        soft_mc: u128,
        hard_mc: u128,
        params: DealParams,
    }
}
}


