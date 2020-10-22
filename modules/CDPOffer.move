module CDPOffer {
    use 0x1::Math;
    use 0x1::Coins;

    use 0x1::Signer;
    use 0x1::Event;

    const INCORRECT_LTV_ERROR: u64 = 1;
    const NO_ORACLE_PRICE_ERROR: u64 = 2;
    const OFFER_DOES_NOT_EXIST: u64 = 5;
    const OFFER_ALREADY_EXISTS: u64 = 6;
    const NOT_ENOUGH_CURRENCY_AVAILABLE_ERROR: u64 = 7;

    resource struct T<Offered: copyable, Collateral: copyable> {
        available_currency: u128,
        // <= 0.66
        ltv: Math::Number,
        interest_rate: Math::Number,
    }

    struct CDPOfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        available_currency: u128,
        // <= 0.66
        ltv: Math::Number,
        interest_rate: Math::Number,
    }

    struct CDPOfferCurrencyRefilled<Offered: copyable, Collateral: copyable> {
        currency: u128,
    }

    struct CDPOfferCurrencyBorrowed<Offered: copyable, Collateral: copyable> {
        currency: u128,
    }

    public fun create<Offered: copyable, Collateral: copyable>(account: &signer, available_currency: u128, ltv: Math::Number, interest_rate: Math::Number) {
        assert(!exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_ALREADY_EXISTS);
        // copy could be removed with U256::lt method implemented
        assert(Math::lt(copy ltv, Math::create_from_decimal(67, 2)), INCORRECT_LTV_ERROR);
        assert(Coins::has_price<Offered, Collateral>(), NO_ORACLE_PRICE_ERROR);

        let offer = T<Offered, Collateral> {
            available_currency, ltv: copy ltv, interest_rate: copy interest_rate
        };
        move_to(account, offer);

        Event::emit(
            account,
            CDPOfferCreatedEvent<Offered, Collateral> {
                available_currency,
                ltv,
                interest_rate,
            }
        );
    }

    public fun refill<Offered: copyable, Collateral: copyable>(account: &signer, currency: u128) acquires T {
        assert(exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_DOES_NOT_EXIST);

        let T { available_currency, ltv, interest_rate } = move_from<T<Offered, Collateral>>(Signer::address_of(account));
        let available_currency = available_currency + currency;
        move_to(account, T<Offered, Collateral> { available_currency, ltv, interest_rate });

        Event::emit(
            account,
            CDPOfferCurrencyRefilled<Offered, Collateral> { currency }
        );
    }

    public fun borrow_currency<Offered: copyable, Collateral: copyable>(account: &signer, currency: u128) acquires T {
        assert(exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_DOES_NOT_EXIST);
        assert(
            currency <= borrow_global<T<Offered, Collateral>>(Signer::address_of(account)).available_currency,
            NOT_ENOUGH_CURRENCY_AVAILABLE_ERROR
        );

        let T { available_currency, ltv, interest_rate } = move_from<T<Offered, Collateral>>(Signer::address_of(account));
        let available_currency = available_currency - currency;
        move_to(account, T<Offered, Collateral> { available_currency, ltv, interest_rate });

        Event::emit(
            account,
            CDPOfferCurrencyBorrowed<Offered, Collateral> { currency }
        );
    }
}



