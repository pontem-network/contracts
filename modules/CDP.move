address 0x1 {
module CDP {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Signer;
    use 0x1::Event;
    use 0x1::Coins;
    use 0x1::Math;
    use 0x1::Math::num;

    const HARD_MARGIN_CALL: u128 = 130;
    const EXCHANGE_RATE_DECIMALS: u8 = 8;

    // offer creation constants start with 100
    const ERR_BANK_DOES_NOT_EXIST: u64 = 101;
    const ERR_NO_ORACLE_PRICE: u64 = 102;
    const ERR_INCORRECT_LTV: u64 = 103;

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
    ): Dfinance::T<Offered> acquires Bank {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let price = Coins::get_price<Offered, Collateral>();

        let offered_dec = Dfinance::decimals<Offered>();
        let collateral_dec = Dfinance::decimals<Collateral>();
        let collateral_amount = Dfinance::value(&collateral);

        assert(amount_wanted > 0, ERR_ZERO_AMOUNT);
        assert(collateral_amount > 0, ERR_ZERO_AMOUNT);

        // MAX OFFER in Offered (1to1) = COLL_AMT * COLL_OFF_PRICE;
        let deal_ltv = {
            let collateral_num = num(collateral_amount, collateral_dec);
            let price_num = num(price, EXCHANGE_RATE_DECIMALS);
            let wanted_num = num(amount_wanted, offered_dec);

            let ltv_num = Math::div(
                wanted_num,
                Math::mul(collateral_num, price_num)
            );
            ((Math::scale_to_decimals(ltv_num, 2) * 100) as u64)
        };

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        let max_ltv = bank.max_ltv;
        assert(deal_ltv < max_ltv, ERR_INCORRECT_LTV);

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, amount_wanted);

        Account::deposit(borrower_acc, bank_addr, collateral);

        let deal = Deal<Offered, Collateral> {};
        move_to(borrower_acc, deal);

        offered
    }

    struct BankCreatedEvent<Offered: copy + store, Collateral: copy + store> has copy {
        owner: address,
        deposit_amount: u128,
        max_ltv: u64
    }
}
}