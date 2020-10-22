module CDPOffer {
    use 0x1::Coins;
    use 0x1::Dfinance;

    use 0x1::Signer;
    use 0x1::Event;

    const MAX_LTV: u64 = 6700;  // 67.00%

    const INCORRECT_LTV_ERROR: u64 = 1;
    const NO_ORACLE_PRICE_ERROR: u64 = 2;
    const OFFER_DOES_NOT_EXIST: u64 = 5;
    const OFFER_ALREADY_EXISTS: u64 = 6;
    const NOT_ENOUGH_CURRENCY_AVAILABLE_ERROR: u64 = 7;

    resource struct T<Offered: copyable, Collateral: copyable> {
        available_amount: Dfinance::T<Offered>,
        // < 6700
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
        // 2 signs after comma

    }

    struct CDPOfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        available_amount: u128,
        // < 6700
        ltv: u64,
        interest_rate: u64,
    }

    struct CDPOfferCurrencyDeposited<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    struct CDPOfferCurrencyBorrowed<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    public fun create<Offered: copyable, Collateral: copyable>(
        account: &signer,
        available_amount: Dfinance::T<Offered>,
        ltv: u64,
        interest_rate: u64
    ) {
        assert(!exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_ALREADY_EXISTS);

        assert(ltv < MAX_LTV, INCORRECT_LTV_ERROR);
        assert(Coins::has_price<Offered, Collateral>(), NO_ORACLE_PRICE_ERROR);

        let amount_num = Dfinance::value(&available_amount);
        let offer = T<Offered, Collateral> { available_amount, ltv, interest_rate };
        move_to(account, offer);

        Event::emit(
            account,
            CDPOfferCreatedEvent<Offered, Collateral> {
                available_amount: amount_num,
                ltv,
                interest_rate,
            }
        );
    }

    public fun deposit_amount<Offered: copyable, Collateral: copyable>(
        account: &signer,
        amount: Dfinance::T<Offered>
    ) acquires T {
        assert(exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_DOES_NOT_EXIST);

        let T { available_amount, ltv, interest_rate } = move_from<T<Offered, Collateral>>(Signer::address_of(account));
        let amount_deposited_num = Dfinance::value(&amount);
        let available_amount_changed = Dfinance::join<Offered>(available_amount, amount);
        move_to(account, T<Offered, Collateral> {
            available_amount: available_amount_changed,
            ltv,
            interest_rate
        });

        Event::emit(
            account,
            CDPOfferCurrencyDeposited<Offered, Collateral> { amount: amount_deposited_num }
        );
    }

    public fun borrow_amount<Offered: copyable, Collateral: copyable>(
        account: &signer,
        amount: u128
    ): Dfinance::T<Offered> acquires T {
        assert(exists<T<Offered, Collateral>>(Signer::address_of(account)), OFFER_DOES_NOT_EXIST);

        let offer = borrow_global_mut<T<Offered, Collateral>>(Signer::address_of(account));
        let borrowed = Dfinance::withdraw<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            CDPOfferCurrencyBorrowed<Offered, Collateral> { amount }
        );
        borrowed
    }
}



