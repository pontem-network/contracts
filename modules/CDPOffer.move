module CDPOffer {
    use 0x1::Coins;
    use 0x1::Dfinance;

    use 0x1::Signer;
    use 0x1::Event;

    const MAX_LTV: u64 = 6700;  // 67.00%

    const ERR_INCORRECT_LTV: u64 = 1;
    const ERR_NO_ORACLE_PRICE: u64 = 2;
    const ERR_OFFER_DOES_NOT_EXIST: u64 = 5;
    const ERR_OFFER_ALREADY_EXISTS: u64 = 6;
    const ERR_NOT_ENOUGH_CURRENCY_AVAILABLE: u64 = 7;

    resource struct T<Offered: copyable, Collateral: copyable> {
        available_amount: Dfinance::T<Offered>,
        // < 6700
        ltv: u64,
        // 2 signs after comma
        interest_rate: u64,
        // 2 signs after comma

    }

    struct OfferCreatedEvent<Offered: copyable, Collateral: copyable> {
        available_amount: u128,
        // < 6700
        ltv: u64,
        interest_rate: u64,
    }

    struct CurrencyDepositedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    struct CurrencyBorrowedEvent<Offered: copyable, Collateral: copyable> {
        amount: u128,
    }

    public fun create<Offered: copyable, Collateral: copyable>(
        account: &signer,
        available_amount: Dfinance::T<Offered>,
        ltv: u64,
        interest_rate: u64
    ) {
        assert(!exists<T<Offered, Collateral>>(Signer::address_of(account)), ERR_OFFER_ALREADY_EXISTS);

        assert(ltv < MAX_LTV, ERR_INCORRECT_LTV);
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);

        let amount_num = Dfinance::value(&available_amount);
        let offer = T<Offered, Collateral> { available_amount, ltv, interest_rate };
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

    public fun deposit_amount<Offered: copyable, Collateral: copyable>(
        account: &signer,
        offer_address: address,
        amount: Dfinance::T<Offered>
    ) acquires T {
        assert(exists<T<Offered, Collateral>>(offer_address), ERR_OFFER_DOES_NOT_EXIST);

        let offer = borrow_global_mut<T<Offered, Collateral>>(offer_address);
        let amount_deposited_num = Dfinance::value(&amount);
        Dfinance::deposit<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            CurrencyDepositedEvent<Offered, Collateral> { amount: amount_deposited_num }
        );
    }

    public fun borrow_amount<Offered: copyable, Collateral: copyable>(
        account: &signer,
        amount: u128
    ): Dfinance::T<Offered> acquires T {
        assert(exists<T<Offered, Collateral>>(Signer::address_of(account)), ERR_OFFER_DOES_NOT_EXIST);

        let offer = borrow_global_mut<T<Offered, Collateral>>(Signer::address_of(account));
        let borrowed = Dfinance::withdraw<Offered>(&mut offer.available_amount, amount);

        Event::emit(
            account,
            CurrencyBorrowedEvent<Offered, Collateral> { amount }
        );
        borrowed
    }
}



