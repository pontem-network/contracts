address 0x1 {
module CDP {
    use 0x1::Dfinance;
    use 0x1::Signer;
    use 0x1::Event;
    use 0x1::Coins;
    use 0x1::Math::num;

    const HARD_MARGIN_CALL: u128 = 130;
    const EXCHANGE_RATE_DECIMALS: u8 = 8;

    // offer creation constants start with 100
    const ERR_BANK_DOES_NOT_EXIST: u64 = 101;
    const ERR_NO_ORACLE_PRICE: u64 = 102;

    const ERR_ZERO_AMOUNT: u64 = 201;

    struct Bank<Offered: copy + store, Collateral: copy + store> has key {
        deposit: Dfinance::T<Offered>,

        /// Loan-to-Value ratio, < 6700, 2 signs after comma
        max_ltv: u64
    }

    public fun create_bank<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        deposit: Dfinance::T<Offered>,
        max_ltv: u64
    ) {
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);

        let deposit_amount = Dfinance::value(&deposit);

        let bank = Bank<Offered, Collateral> { deposit, max_ltv };
        move_to(owner_acc, bank);

        Event::emit(
            owner_acc,
            BankCreatedEvent<Offered, Collateral> {
                owner: Signer::address_of(owner_acc),
                deposit_amount,
                max_ltv,
            });
    }

    struct Deal<Offered: copy + store, Collateral: copy + store> has key {}

    public fun create_deal<Offered: copy + store, Collateral: copy + store>(
        borrower_acc: &signer,
        bank_addr: address,
        collateral: Dfinance::T<Collateral>,
        amount_wanted: u128
    ) {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let price = Coins::get_price<Collateral, Offered>();
//        let price = num(Coins::get_price<Collateral, Offered>(), EXCHANGE_RATE_DECIMALS);

        let offered_dec = Dfinance::decimals<Offered>();
        let collateral_dec = Dfinance::decimals<Collateral>();
        let collateral_amount = Dfinance::value(&collateral);

        assert(amount_wanted > 0, ERR_ZERO_AMOUNT);
        assert(collateral_amount > 0, ERR_ZERO_AMOUNT);

        // MAX OFFER in Offered (1to1) = COLL_AMT * COLL_OFF_PRICE;
        let max_offer = {
            let collateral_num = num(collateral_amount, collateral_dec);
            let price_num = num(price, EXCHANGE_RATE_DECIMALS);
            let max_off = Math::mul(collateral_num, copy price);

            max_off
        };
    }

    struct BankCreatedEvent<Offered: copy + store, Collateral: copy + store> has copy {
        owner: address,
        deposit_amount: u128,
        max_ltv: u64
    }
}
}