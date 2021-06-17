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

    // deal close params
    const ERR_HARD_MC_HAS_OCCURRED: u64 = 301;
    const ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED: u64 = 302;
    const ERR_DEAL_DOES_NOT_EXIST: u64 = 303;

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

    struct Deal<Offered: copy + store, Collateral: copy + store> has key {
        bank_owner_addr: address,
        collateral: Dfinance::T<Collateral>,
        offered_amount: u128
    }

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

            let ltv_num = Math::div(
                num(amount_wanted, offered_dec),
                Math::mul(collateral_num, price_num)
            );
            ((Math::scale_to_decimals(ltv_num, 2) * 100) as u64)
        };

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        let max_ltv = bank.max_ltv;
        assert(deal_ltv < max_ltv, ERR_INCORRECT_LTV);

        let deal = Deal<Offered, Collateral> {
            bank_owner_addr: bank_addr,
            collateral,
            offered_amount: amount_wanted
        };
        move_to(borrower_acc, deal);

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, amount_wanted);
        offered
    }

    public fun close_deal_by_margin_call<Offered: copy + store, Collateral: copy + store>(
        acc: &signer,
        borrower_addr: address
    ) acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);
        let Deal {
            bank_owner_addr,
            collateral,
            offered_amount
        } = move_from<Deal<Offered, Collateral>>(borrower_addr);

        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let collateral_amount = Dfinance::value(&collateral);
        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collateral_num = num(collateral_amount, collateral_decimals);

        let offered_for_collateral = Math::mul(price_num, collateral_num);

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(offered_amount, offered_decimals);
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        let hard_mc_num = Math::mul(offered_num, hard_mc_multiplier);

        assert(
            Math::scale_to_decimals(offered_for_collateral, 18)
            <= Math::scale_to_decimals(hard_mc_num, 18),
            ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED
        );
        Account::deposit(acc, bank_owner_addr, collateral);
    }

    fun compute_margin_call(offered_num: Math::Num): Math::Num {
        // HMC = OFFERED_COINS * 1.3
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        Math::mul(offered_num, hard_mc_multiplier)
    }

    struct BankCreatedEvent<Offered: copy + store, Collateral: copy + store> has copy {
        owner: address,
        deposit_amount: u128,
        max_ltv: u64
    }

    struct DealCreatedEvent<Offered: copy + store, Collateral: copy + store> {

    }

    struct DealClosedEvent<Offered: copy + store, Collateral: copy + store> {

    }
}
}