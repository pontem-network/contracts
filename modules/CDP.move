address 0x1 {
module CDP {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Signer;
    use 0x1::Event;
    use 0x1::Coins;
    use 0x1::Time;
    use 0x1::Math;
    use 0x1::Math::num;

    const GLOBAL_MAX_LTV: u64 = 6600;  // 66.00%
    const GLOBAL_MAX_INTEREST_RATE: u64 = 10000;  // 100.00%
    const HARD_MARGIN_CALL: u128 = 130;

    const EXCHANGE_RATE_DECIMALS: u8 = 8;
    const INTEREST_RATE_DECIMALS: u8 = 4;
    const MARGIN_CALL_DECIMALS: u8 = 2;

    // offer creation constants start with 100
    const ERR_BANK_DOES_NOT_EXIST: u64 = 101;
    const ERR_NO_ORACLE_PRICE: u64 = 102;
    const ERR_INCORRECT_LTV: u64 = 103;
    const ERR_INCORRECT_INTEREST_RATE: u64 = 104;

    const ERR_ZERO_AMOUNT: u64 = 201;
    const ERR_ZERO_COLLATERAL: u64 = 201;

    // deal close params
    const ERR_HARD_MC_HAS_OCCURRED: u64 = 301;
    const ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED: u64 = 302;
    const ERR_DEAL_DOES_NOT_EXIST: u64 = 303;
    const ERR_INVALID_PAYBACK_AMOUNT: u64 = 303;

    struct Bank<Offered: copy + store, Collateral: copy + store> has key {
        deposit: Dfinance::T<Offered>,

        /// Loan-to-Value ratio: [0, 6600] (2 signs after comma)
        max_ltv: u64,
        /// loan interest rate: [0, 10000] (2 signs after comma)
        interest_rate_per_year: u64,
    }

    public fun create_bank<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        deposit: Dfinance::T<Offered>,
        max_ltv: u64,
        interest_rate_per_year: u64,
    ) {
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);
        assert(0u64 < max_ltv && max_ltv <= GLOBAL_MAX_LTV, ERR_INCORRECT_LTV);
        assert(interest_rate_per_year <= GLOBAL_MAX_INTEREST_RATE, ERR_INCORRECT_INTEREST_RATE);

        let deposit_amount = Dfinance::value(&deposit);

        let bank = Bank<Offered, Collateral> { deposit, max_ltv, interest_rate_per_year };
        move_to(owner_acc, bank);

        Event::emit(
            owner_acc,
            BankCreatedEvent<Offered, Collateral> {
                owner: Signer::address_of(owner_acc),
                deposit_amount,
                max_ltv,
                interest_rate_per_year,
            });
    }

    struct Deal<Offered: copy + store, Collateral: copy + store> has key {
        bank_owner_addr: address,
        collateral: Dfinance::T<Collateral>,
        offered_amount: u128,
        created_at: u64,
        interest_rate_per_year: u64,
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
        assert(collateral_amount > 0, ERR_ZERO_COLLATERAL);

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
        assert(deal_ltv <= max_ltv, ERR_INCORRECT_LTV);

        let created_at = Time::now();
        let interest_rate_per_year = bank.interest_rate_per_year;

        let deal = Deal<Offered, Collateral> {
            bank_owner_addr: bank_addr,
            collateral,
            offered_amount: amount_wanted,
            created_at,
            interest_rate_per_year,
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

        let loan_amount_num = get_loan_amount<Offered, Collateral>(borrower_addr);
        let Deal {
            bank_owner_addr,
            collateral,
            offered_amount: _,
            created_at: _,
            interest_rate_per_year: _,
        } = move_from<Deal<Offered, Collateral>>(borrower_addr);

        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let collateral_amount = Dfinance::value(&collateral);
        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collateral_num = num(collateral_amount, collateral_decimals);

        let offered_for_collateral = Math::mul(copy price_num, collateral_num);

        let hard_mc_multiplier = num(HARD_MARGIN_CALL, MARGIN_CALL_DECIMALS);
        let hard_mc_num = Math::mul(copy loan_amount_num, hard_mc_multiplier);
        assert(
            Math::scale_to_decimals(offered_for_collateral, 18)
            <= Math::scale_to_decimals(hard_mc_num, 18),
            ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED
        );

        let owner_collateral_num = Math::div(loan_amount_num, price_num);
        let owner_collateral_amount = Math::scale_to_decimals(owner_collateral_num, collateral_decimals);
        // TODO: if offered + interest > collateral?

        let owner_collateral = Dfinance::withdraw(&mut collateral, owner_collateral_amount);
        Account::deposit(acc, bank_owner_addr, owner_collateral);
        Account::deposit(acc, borrower_addr, collateral);
    }

    public fun pay_back<Offered: copy + store, Collateral: copy + store>(
        acc: &signer,
        borrower_addr: address,
        offered: Dfinance::T<Offered>,
    ): Dfinance::T<Collateral> acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let offered_decimals = Dfinance::decimals<Offered>();

        let loan_amount_num = get_loan_amount<Offered, Collateral>(borrower_addr);
        let loan_amount = Math::scale_to_decimals(loan_amount_num, offered_decimals);
        assert(
            Dfinance::value(&offered) == loan_amount,
            ERR_INVALID_PAYBACK_AMOUNT
        );
        let Deal {
            bank_owner_addr,
            collateral,
            offered_amount: _,
            created_at: _,
            interest_rate_per_year: _,
        } = move_from<Deal<Offered, Collateral>>(borrower_addr);

        Account::deposit(acc, bank_owner_addr, offered);
        collateral
    }

    public fun get_loan_amount<Offered: copy + store, Collateral: copy + store>(
        borrower_addr: address,
    ): Math::Num acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global<Deal<Offered, Collateral>>(borrower_addr);
        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(deal.offered_amount, offered_decimals);

        let interest_rate_num = num((deal.interest_rate_per_year as u128), INTEREST_RATE_DECIMALS);
        let days_passed = Time::days_from(deal.created_at) + 1;
        let days_passed_num = num((days_passed as u128), 0);

        let days_in_year = num(365, 0);
        let multiplier = Math::div(Math::mul(days_passed_num, interest_rate_num), days_in_year);
        let offered_with_interest_num =
            Math::add(
                copy offered_num,
                Math::mul(offered_num, multiplier)
            );
        offered_with_interest_num
    }

    fun compute_margin_call(offered_num: Math::Num): Math::Num {
        // HMC = OFFERED_COINS * 1.3
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        Math::mul(offered_num, hard_mc_multiplier)
    }

    struct BankCreatedEvent<Offered: copy + store, Collateral: copy + store> has copy {
        owner: address,
        deposit_amount: u128,
        max_ltv: u64,
        interest_rate_per_year: u64,
    }

    struct DealCreatedEvent<Offered: copy + store, Collateral: copy + store> {}

    struct DealClosedEvent<Offered: copy + store, Collateral: copy + store> {}
}
}