address 0x1 {
module CDP2 {
    use 0x1::Coins;
    use 0x1::Dfinance;
    use 0x1::Math;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Event;

    const MAX_LTV: u64 = 6700;  // 67.00%
    const SOFT_MARGIN_CALL: u64 = 150;
    const HARD_MARGIN_CALL: u64 = 130;

    const ERR_INCORRECT_LTV: u64 = 1;
    const ERR_NO_ORACLE_PRICE: u64 = 2;
    const ERR_OFFER_DOES_NOT_EXIST: u64 = 5;
    const ERR_DEAL_DOES_NOT_EXIST: u64 = 51;
    const ERR_OFFER_ALREADY_EXISTS: u64 = 6;
    const ERR_CDP_ALREADY_EXISTS: u64 = 61;
    const ERR_NOT_ENOUGH_CURRENCY_AVAILABLE: u64 = 7;

    resource struct Offer<Offered: copyable, Collateral: copyable> {
        available_amount: Dfinance::T<Offered>,
        // < 6700, 2 signs after comma
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
    }

    resource struct Deal<Offered, Collateral> {
        collateral: Dfinance::T<Collateral>,
        offer_owner_address: address,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }

    public fun create_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        available_amount: Dfinance::T<Offered>,
        ltv: u64,
        interest_rate: u64
    ) {
        assert(ltv < MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);

        assert(!exists<Offer<Offered, Collateral>>(Signer::address_of(account)), ERR_OFFER_ALREADY_EXISTS);

        let amount_num = Dfinance::value(&available_amount);
        let offer = Offer<Offered, Collateral> { available_amount, ltv, interest_rate };
        move_to(account, offer);

        Event::emit(
            account,
            OfferCreatedEvent<Offered, Collateral> {
                available_amount: amount_num,
                ltv,
                interest_rate,
            }
        );
    }

    public fun deposit_amount_to_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        offer_owner_address: address,
        amount: Dfinance::T<Offered>
    ) acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(offer_owner_address);
        let amount_deposited_num = Dfinance::value(&amount);
        Dfinance::deposit<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            OfferDepositedEvent<Offered, Collateral> { amount: amount_deposited_num }
        );
    }

    public fun make_deal<Offered: copyable, Collateral: copyable>(
        borrower_account: &signer,
        offer_owner_address: address,
        collateral: Dfinance::T<Collateral>,
        ltv: u64
    ): Dfinance::T<Offered>
    acquires Offer {
        assert(
            exists<Offer<Offered, Collateral>>(offer_owner_address),
            ERR_OFFER_DOES_NOT_EXIST
        );
        assert(
            !exists<Deal<Offered, Collateral>>(Signer::address_of(borrower_account)),
            ERR_CDP_ALREADY_EXISTS
        );

        let offer_ltv = get_offer_ltv<Offered, Collateral>(offer_owner_address);
        assert(ltv <= offer_ltv, ERR_INCORRECT_LTV);

        let collaretal_value_u128 = Dfinance::value<Collateral>(&collateral);
        let offered_amount = compute_collateral_value<Offered, Collateral>(collaretal_value_u128, ltv);

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered = withdraw_amount_from_offer<Offered, Collateral>(
            borrower_account,
            offer_owner_address,
            Math::as_scaled_u128(copy offered_amount, Dfinance::decimals<Offered>())
        );

        let (soft_mc, hard_mc) = compute_margin_calls(offered_amount, offered_decimals);

        let borrower_address = Signer::address_of(borrower_account);
        move_to(borrower_account, Deal<Offered, Collateral> {
            collateral,
            offer_owner_address: offer_owner_address,
            ltv,
            soft_mc,
            hard_mc
        });
        Event::emit(
            borrower_account,
            DealCreated<Offered, Collateral> {
                offer_owner_address,
                borrower_address,
                offered: Dfinance::value(&offered),
                collateral: collaretal_value_u128,
                ltv,
                soft_mc,
                hard_mc,
            });
        offered
    }

    public fun check_and_release_deal_if_margin_call_occurred<Offered: copyable, Collateral: copyable>(
        caller_account: &signer,
        borrower_address: address,
    ) acquires Deal {
        assert(
            exists<Deal<Offered, Collateral>>(borrower_address),
            ERR_DEAL_DOES_NOT_EXIST
        );

        let deal = borrow_global<Deal<Offered, Collateral>>(borrower_address);
        let collateral_value_stored = Dfinance::value(&deal.collateral);
        let collateral_value_unscaled = compute_collateral_value<Offered, Collateral>(
            collateral_value_stored,
            10000
        );
        // same dimension as margin calls
        let collateral_value = Math::as_scaled_u128(collateral_value_unscaled, Dfinance::decimals<Offered>());
        if (collateral_value > deal.hard_mc) return;

        // remove deal
        let Deal {
            collateral,
            offer_owner_address,
            ltv,
            soft_mc,
            hard_mc
        } = move_from<Deal<Offered, Collateral>>(borrower_address);

        // deposit token
        Account::deposit<Collateral>(caller_account, offer_owner_address, collateral);

        Event::emit(
            caller_account,
            DealClosed<Offered, Collateral> {
                offer_owner_address,
                borrower_address,
                collateral: collateral_value_stored,
                collateral_in_offered: collateral_value,
                ltv,
                soft_mc,
                hard_mc,
            })
    }

    fun get_offer_ltv<Offered: copyable, Collateral: copyable>(offer_address: address): u64 acquires Offer {
        let offer = borrow_global<Offer<Offered, Collateral>>(offer_address);
        offer.ltv
    }

    fun withdraw_amount_from_offer<Offered: copyable, Collateral: copyable>(
        borrower_account: & signer,
        offer_address: address,
        amount: u128
    ): Dfinance::T<Offered> acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(offer_address);
        let borrowed = Dfinance::withdraw<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            borrower_account,
            OfferDepositBorrowedEvent<Offered, Collateral> { amount }
        );
        borrowed
    }

    fun compute_margin_calls(offered_amount: Math::Number, offered_scale: u8): (u128, u128) {
        let soft_mc_multiplier = Math::create_from_decimal(SOFT_MARGIN_CALL, 2);
        let soft_mc = Math::mul(copy offered_amount, soft_mc_multiplier);

        let hard_mc_multiplier = Math::create_from_decimal(HARD_MARGIN_CALL, 2);
        let hard_mc = Math::mul(copy offered_amount, hard_mc_multiplier);

        (Math::as_scaled_u128(soft_mc, offered_scale), Math::as_scaled_u128(hard_mc, offered_scale))
    }

    fun compute_collateral_value<Offered: copyable, Collateral: copyable>(collateral: u128, ltv: u64): Math::Number {
        let exchange_rate_u128 = Coins::get_price<Offered, Collateral>();
        let exchange_rate = Math::create_from_u128_decimal(exchange_rate_u128, 8);
        let ltv_num = Math::create_from_decimal(ltv, 4);

        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collaretal_value = Math::create_from_u128_decimal(collateral, collateral_decimals);

        let offered_amount = Math::mul(
            Math::mul(
                exchange_rate,
                collaretal_value
            ),
            ltv_num
        );
        offered_amount
    }

    struct OfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        available_amount: u128,
        // < 6700
        ltv: u64,
        interest_rate: u64,
    }

    struct OfferDepositedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    struct OfferDepositBorrowedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    struct DealCreated<Offered: copyable, Collateral: copyable> {
        offer_owner_address: address,
        borrower_address: address,
        offered: u128,
        collateral: u128,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }

    struct DealClosed<Offered: copyable, Collateral: copyable> {
        offer_owner_address: address,
        borrower_address: address,
        collateral: u128,
        collateral_in_offered: u128,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }
}
}


