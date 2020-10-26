address 0x1 {
module CDP2 {
    use 0x1::Coins;
    use 0x1::Dfinance;
    use 0x1::Math::{Self, Num, num_create, num_unpack};
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Event;
    use 0x1::Time;

    const MAX_LTV: u64 = 6600;  // 66.00%
    const SOFT_MARGIN_CALL: u128 = 150;
    const HARD_MARGIN_CALL: u128 = 130;
    const SECONDS_IN_DAY: u128 = 86400;
    const EXCHANGE_RATE_DECIMALS: u8 = 8;
    const LTV_DECIMALS: u8 = 4;
    const INTEREST_RATE_DECIMALS: u8 = 4;

    const ERR_INCORRECT_LTV: u64 = 1;
    const ERR_NO_ORACLE_PRICE: u64 = 2;
    const ERR_HARD_MC_HAS_OCCURRED: u64 = 3;
    const ERR_HARD_MC_HAS_NOT_OCCURRED: u64 = 31;

    resource struct Offer<Offered: copyable, Collateral: copyable> {
        available_amount: Dfinance::T<Offered>,
        // < 6700, 2 signs after comma
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
    }

    resource struct Deal<Offered, Collateral> {
        offered: u128,
        collateral: Dfinance::T<Collateral>,
        created_at: u64,
        interest_rate: u64,
        lender: address,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }

    public fun has_deal<Offered: copyable, Collateral: copyable>(borrower: address): bool {
        exists<Deal<Offered, Collateral>>(borrower)
    }

    public fun has_offer<Offered: copyable, Collateral: copyable>(lender: address): bool {
        exists<Offer<Offered, Collateral>>(lender)
    }

    public fun create_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        available_amount: Dfinance::T<Offered>,
        ltv: u64,
        interest_rate: u64
    ) {
        assert(ltv <= MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);

        let amount_num = Dfinance::value(&available_amount);
        let offer = Offer<Offered, Collateral> { available_amount, ltv, interest_rate };
        move_to(account, offer);

        Event::emit(
            account,
            OfferCreatedEvent<Offered, Collateral> {
                available_amount: amount_num,
                ltv,
                interest_rate,
                lender: Signer::address_of(account),
            }
        );
    }

    public fun deposit_amount_to_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        amount: Dfinance::T<Offered>
    ) acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);
        let amount_deposited_num = Dfinance::value(&amount);
        Dfinance::deposit<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            OfferDepositedEvent<Offered, Collateral> {
                amount: amount_deposited_num,
                lender,
            }
        );
    }

    public fun make_deal<Offered: copyable, Collateral: copyable>(
        account: &signer,
        lender: address,
        collateral: Dfinance::T<Collateral>,
        ltv: u64
    ): Dfinance::T<Offered> acquires Offer {
        let offer = borrow_global_mut<Offer<Offered, Collateral>>(lender);

        let offer_ltv = offer.ltv;
        let offer_interest_rate = offer.interest_rate;

        assert(ltv <= offer_ltv, ERR_INCORRECT_LTV);

        let collateral_value_u128 = Dfinance::value<Collateral>(&collateral);
        let offered_num = compute_offered_value_for_collateral<Offered, Collateral>(collateral_value_u128, ltv);
        let (offered_value, _) = num_unpack(copy offered_num);

        let offered = withdraw_amount_from_offer<Offered, Collateral>(
            account,
            offer,
            lender,
            offered_value
        );
        let (soft_mc, hard_mc) = compute_margin_calls(offered_num);

        let offered_value = Dfinance::value(&offered);
        let created_at = Time::now();
        let borrower = Signer::address_of(account);
        move_to(
            account,
            Deal<Offered, Collateral> {
                offered: offered_value,
                collateral,
                created_at,
                interest_rate: offer_interest_rate,
                lender,
                ltv,
                soft_mc,
                hard_mc
            });
        Event::emit(
            account,
            DealCreatedEvent<Offered, Collateral> {
                lender,
                borrower,
                offered: offered_value,
                collateral: collateral_value_u128,
                interest_rate: offer_interest_rate,
                created_at,
                ltv,
                soft_mc,
                hard_mc,
            });
        offered
    }

    public fun release_deal_on_mc_and_deposit_collateral<Offered: copyable, Collateral: copyable>(
        account: &signer,
        borrower: address,
    ) acquires Deal {
        let Deal {
            offered: _,
            collateral,
            created_at: _,
            interest_rate,
            lender,
            ltv,
            soft_mc,
            hard_mc
        } = move_from<Deal<Offered, Collateral>>(borrower);

        let collateral_value_stored = Dfinance::value(&collateral);
        let offered_num = compute_offered_value_for_collateral<Offered, Collateral>(
            collateral_value_stored,
            10000
        );
        // same dimension as margin calls
        let (offered_for_collateral, _) = num_unpack(offered_num);
        assert(
            offered_for_collateral <= hard_mc,
            ERR_HARD_MC_HAS_NOT_OCCURRED
        );

        // deposit token
        Account::deposit<Collateral>(account, lender, collateral);

        Event::emit(
            account,
            DealClosedOnMarginCallEvent<Offered, Collateral> {
                lender,
                borrower,
                collateral: collateral_value_stored,
                collateral_in_offered: offered_for_collateral,
                closed_at: Time::now(),
                interest_rate,
                ltv,
                soft_mc,
                hard_mc,
            });
    }

    public fun return_offered_and_release_collateral<Offered: copyable, Collateral: copyable>(
        account: &signer
    ): Dfinance::T<Collateral> acquires Deal {
        let borrower = Signer::address_of(account);
        let Deal {
            offered,
            collateral,
            created_at,
            interest_rate,
            lender,
            ltv,
            soft_mc,
            hard_mc
        } = move_from<Deal<Offered, Collateral>>(borrower);

        let collateral_value_stored = Dfinance::value(&collateral);
        let offered_num_for_collateral = compute_offered_value_for_collateral<Offered, Collateral>(
            collateral_value_stored,
            10000
        );
        // same dimension as margin calls
        let (offered_for_collateral, _) = num_unpack(offered_num_for_collateral);
        assert(
            offered_for_collateral > hard_mc,
            ERR_HARD_MC_HAS_OCCURRED
        );

        let now = Time::now();
        let days_since_created = ((now - created_at) as u128) / SECONDS_IN_DAY;
        let days_since_created = if (days_since_created != 0) days_since_created else 1;

        let days_since_created_multiplier = Math::div(
            num_create(days_since_created * Math::pow_10(18), 18),
            num_create(365, 0)
        );

        let offered_num = num_create(offered, Dfinance::decimals<Offered>());
        let interest_rate_num = num_create((interest_rate as u128), INTEREST_RATE_DECIMALS);

        let offered_value_to_return = Math::add(
            copy offered_num,
            Math::mul(
                Math::mul(
                    offered_num,
                    interest_rate_num
                ),
                days_since_created_multiplier
            )
        );

        let (offered_value, _) = num_unpack(offered_value_to_return);

        let offered = Account::withdraw_from_sender<Offered>(account, offered_value);
        Account::deposit<Offered>(account, lender, offered);

        Event::emit(
            account,
            DealClosedOnMarginCallEvent<Offered, Collateral> {
                lender,
                borrower,
                collateral: collateral_value_stored,
                collateral_in_offered: offered_for_collateral,
                closed_at: Time::now(),
                interest_rate,
                ltv,
                soft_mc,
                hard_mc,
            });
        collateral
    }

    fun withdraw_amount_from_offer<Offered: copyable, Collateral: copyable>(
        account: &signer,
        offer: &mut Offer<Offered, Collateral>,
        lender: address,
        amount: u128
    ): Dfinance::T<Offered> {
        let borrowed = Dfinance::withdraw<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            OfferDepositBorrowedEvent<Offered, Collateral> {
                amount,
                lender
            }
        );
        borrowed
    }

    fun compute_margin_calls(offered_amount: Num): (u128, u128) {
        let soft_mc_multiplier = num_create(SOFT_MARGIN_CALL, 2);
        let (soft_mc, _) = num_unpack(Math::mul(copy offered_amount, soft_mc_multiplier));

        let hard_mc_multiplier = num_create(HARD_MARGIN_CALL, 2);
        let (hard_mc, _) = num_unpack(Math::mul(offered_amount, hard_mc_multiplier));

        (soft_mc, hard_mc)
    }

    fun compute_offered_value_for_collateral<Offered: copyable, Collateral: copyable>(collateral: u128, ltv: u64): Num {
        let exchange_rate = num_create(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let ltv_rate = num_create((ltv as u128), LTV_DECIMALS);
        let collateral = num_create(collateral, Dfinance::decimals<Collateral>());

        let offered_unscaled = Math::mul(
            Math::mul(exchange_rate, collateral),
            ltv_rate
        );
        let offered_decimals = Dfinance::decimals<Offered>();
        let offered = Math::scale_to_decimals(offered_unscaled, offered_decimals);
        num_create(offered, offered_decimals)
    }

    struct OfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        available_amount: u128,
        // < 6700
        ltv: u64,
        interest_rate: u64,
        lender: address,
    }

    struct OfferDepositedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
        lender: address,
    }

    struct OfferDepositBorrowedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
        lender: address,
    }

    struct DealCreatedEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        offered: u128,
        collateral: u128,
        created_at: u64,
        interest_rate: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }

    struct DealClosedOnBorrowerEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        collateral: u128,
        collateral_in_offered: u128,
        closed_at: u64,
        interest_rate: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }

    struct DealClosedOnMarginCallEvent<Offered: copyable, Collateral: copyable> {
        lender: address,
        borrower: address,
        collateral: u128,
        collateral_in_offered: u128,
        closed_at: u64,
        interest_rate: u64,
        ltv: u64,
        soft_mc: u128,
        hard_mc: u128,
    }
}
}


