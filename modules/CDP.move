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

    const STATUS_HARD_MC: u8 = 91;
    const STATUS_EXPIRED: u8 = 92;
    const STATUS_VALID_CDP: u8 = 93;

    const EXCHANGE_RATE_DECIMALS: u8 = 8;
    const INTEREST_RATE_DECIMALS: u8 = 4;
    const MARGIN_CALL_DECIMALS: u8 = 2;

    // offer creation constants start with 100
    const ERR_BANK_DOES_NOT_EXIST: u64 = 101;
    const ERR_NO_ORACLE_PRICE: u64 = 102;
    const ERR_INCORRECT_LTV: u64 = 103;
    const ERR_INCORRECT_LOAN_TERM: u64 = 1035;
    const ERR_INCORRECT_INTEREST_RATE: u64 = 104;
    const ERR_BANK_IS_NOT_ACTIVE: u64 = 105;
    const ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS: u64 = 106;

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
        /// whether this bank can be used for new cdp deals
        is_active: bool,

        max_loan_term: u64,
        active_deals_count: u64,
    }

    public fun create_bank<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        deposit: Dfinance::T<Offered>,
        max_ltv: u64,
        interest_rate_per_year: u64,
        max_loan_term: u64,
    ) {
        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_ORACLE_PRICE);
        assert(0u64 < max_ltv && max_ltv <= GLOBAL_MAX_LTV, ERR_INCORRECT_LTV);
        assert(interest_rate_per_year <= GLOBAL_MAX_INTEREST_RATE, ERR_INCORRECT_INTEREST_RATE);

        let deposit_amount = Dfinance::value(&deposit);

        let bank =
            Bank<Offered, Collateral> {
                deposit,
                max_ltv,
                interest_rate_per_year,
                is_active: true,
                max_loan_term,
                active_deals_count: 0
            };
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

    public fun add_deposit<Offered: copy + store, Collateral: copy + store>(
        _acc: &signer,
        bank_addr: address,
        deposit: Dfinance::T<Offered>,
    ) acquires Bank {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        Dfinance::deposit(&mut bank.deposit, deposit);
    }

    public fun withdraw_deposit<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        amount: u128,
    ): Dfinance::T<Offered> acquires Bank {
        let bank_addr = Signer::address_of(owner_acc);
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        assert(
            Dfinance::value(&bank.deposit) >= amount,
            ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS
        );

        Dfinance::withdraw(&mut bank.deposit, amount)
    }

    public fun set_interest_rate<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        interest_rate_per_year: u64,
    ) acquires Bank {
        assert(
            interest_rate_per_year < GLOBAL_MAX_INTEREST_RATE,
            ERR_INCORRECT_INTEREST_RATE
        );
        let bank_addr = Signer::address_of(owner_acc);
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        bank.interest_rate_per_year = interest_rate_per_year
    }

    public fun set_max_loan_term<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        max_loan_term: u64,
    ) acquires Bank {
        assert(max_loan_term > 0, ERR_INCORRECT_LOAN_TERM);
        let bank_addr = Signer::address_of(owner_acc);
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        bank.max_loan_term = max_loan_term;
    }

    public fun set_is_active<Offered: copy + store, Collateral: copy + store>(
        owner_acc: &signer,
        is_active: bool,
    ) acquires Bank {
        let bank_addr = Signer::address_of(owner_acc);
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        bank.is_active = is_active;
    }

    struct Deal<Offered: copy + store, Collateral: copy + store> has key {
        bank_owner_addr: address,
        loan_amount_num: Math::Num,
        collateral: Dfinance::T<Collateral>,
        created_at: u64,
        last_borrow_at: u64,
        loan_term: u64,
        interest_rate_per_year: u64,
    }

    public fun create_deal<Offered: copy + store, Collateral: copy + store>(
        borrower_acc: &signer,
        bank_addr: address,
        collateral: Dfinance::T<Collateral>,
        loan_amount_num: Math::Num,
        loan_term: u64,
    ): Dfinance::T<Offered> acquires Bank {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        assert(bank.is_active, ERR_BANK_IS_NOT_ACTIVE);
        assert(loan_term <= bank.max_loan_term, ERR_INCORRECT_LOAN_TERM);

        let loan_amount = Math::value(&loan_amount_num);
        assert(loan_amount > 0, ERR_ZERO_AMOUNT);
        assert(
            Dfinance::value(&bank.deposit) >= loan_amount,
            ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS
        );

        let collateral_amount = Dfinance::value(&collateral);
        assert(collateral_amount > 0, ERR_ZERO_COLLATERAL);

        let interest_rate_per_year = bank.interest_rate_per_year;
        let deal = Deal<Offered, Collateral> {
            bank_owner_addr: bank_addr,
            collateral,
            loan_amount_num,
            created_at: Time::now(),
            last_borrow_at: Time::now(),
            interest_rate_per_year,
            loan_term,
        };

        let loan_amount_with_one_day_interest = compute_loan_amount_with_interest(&deal);
        let deal_ltv =
            compute_ltv<Offered, Collateral>(
                collateral_amount,
                loan_amount_with_one_day_interest
            );
        assert(deal_ltv <= bank.max_ltv, ERR_INCORRECT_LTV);

        move_to(borrower_acc, deal);
        bank.active_deals_count = bank.active_deals_count + 1;

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, loan_amount);
        offered
    }

    public fun borrow_more<Offered: copy + store, Collateral: copy + store>(
        borrower_acc: &signer,
        new_loan_amount_num: Math::Num,
        collateral_amount: u128,
    ): Dfinance::T<Offered> acquires Deal, Bank {
        let borrower_addr = Signer::address_of(borrower_acc);
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let bank = borrow_global_mut<Bank<Offered, Collateral>>(deal.bank_owner_addr);

        let new_loan_amount = Math::value(&new_loan_amount_num);
        assert(new_loan_amount > 0, ERR_ZERO_AMOUNT);
        assert(
            Dfinance::value(&bank.deposit) >= new_loan_amount,
            ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS
        );

        let existing_loan_amount_num = compute_loan_amount_with_interest(deal);
        deal.last_borrow_at = Time::now();
        deal.loan_amount_num = Math::add(existing_loan_amount_num, new_loan_amount_num);

        let new_loan_amount_num = compute_loan_amount_with_interest(deal);
        let new_deal_ltv = compute_ltv<Offered, Collateral>(collateral_amount, new_loan_amount_num);
        assert(new_deal_ltv <= bank.max_ltv, ERR_INCORRECT_LTV);

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, new_loan_amount);
        offered
    }

    public fun pay_back_partially<Offered: copy + store, Collateral: copy + store>(
        acc: &signer,
        borrower_addr: address,
        offered: Dfinance::T<Offered>
    ) acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest(deal);
        let bank_owner_addr = deal.bank_owner_addr;
        let loan_amount_with_interest = Math::value(&loan_amount_with_interest_num);

        let offered_amount = Dfinance::value(&offered);
        assert(
            offered_amount < loan_amount_with_interest,
            ERR_INVALID_PAYBACK_AMOUNT
        );

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(offered_amount, offered_decimals);

        let new_loan_amount_num = Math::sub(loan_amount_with_interest_num, offered_num);
        deal.loan_amount_num = new_loan_amount_num;
        deal.last_borrow_at = Time::now();

        Account::deposit(acc, bank_owner_addr, offered);
    }

    public fun add_collateral<Offered: copy + store, Collateral: copy + store>(
        _acc: &signer,
        borrower_addr: address,
        collateral: Dfinance::T<Collateral>
    ) acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        Dfinance::deposit(&mut deal.collateral, collateral);
    }

    public fun close_deal_by_termination_status<Offered: copy + store, Collateral: copy + store>(
        acc: &signer,
        borrower_addr: address
    ) acquires Deal, Bank {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = move_from<Deal<Offered, Collateral>>(borrower_addr);
        let deal_status = get_deal_status(&deal);
        assert(
            deal_status != STATUS_VALID_CDP,
            ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED
        );

        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest<Offered, Collateral>(&deal);
        let Deal {
            bank_owner_addr,
            collateral,
            loan_amount_num: _,
            created_at: _,
            last_borrow_at: _,
            loan_term: _,
            interest_rate_per_year: _,
        } = deal;

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_owner_addr);
        bank.active_deals_count = bank.active_deals_count - 1;

        let owner_collateral_num = Math::div(loan_amount_with_interest_num, price_num);
        let owner_collateral_amount = Math::value(&owner_collateral_num);
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

        let deal = move_from<Deal<Offered, Collateral>>(borrower_addr);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest<Offered, Collateral>(&deal);
        let loan_amount_with_interest = Math::value(&loan_amount_with_interest_num);
        assert(
            Dfinance::value(&offered) == loan_amount_with_interest,
            ERR_INVALID_PAYBACK_AMOUNT
        );
        let Deal {
            bank_owner_addr,
            collateral,
            loan_amount_num: _,
            created_at: _,
            last_borrow_at: _,
            loan_term: _,
            interest_rate_per_year: _,
        } = deal;

        Account::deposit(acc, bank_owner_addr, offered);
        collateral
    }

    public fun compute_loan_amount_with_interest<Offered: copy + store, Collateral: copy + store>(
        deal: &Deal<Offered, Collateral>,
    ): Math::Num {
        let interest_rate_num = num((deal.interest_rate_per_year as u128), INTEREST_RATE_DECIMALS);
        let days_passed = Time::days_from(deal.last_borrow_at) + 1;
        let days_passed_num = num((days_passed as u128), 0);

        let days_in_year = num(365, 0);
        let multiplier = Math::div(Math::mul(days_passed_num, interest_rate_num), days_in_year);
        let loan_amount_num = Math::copy_num(&deal.loan_amount_num);
        let offered_with_interest_num =
            Math::add(
                copy loan_amount_num,
                Math::mul(loan_amount_num, multiplier)
            );
        offered_with_interest_num
    }

    fun get_deal_status<Offered: copy + store, Collateral: copy + store>(
        deal: &Deal<Offered, Collateral>
    ): u8 {
        let collateral_amount = Dfinance::value(&deal.collateral);
        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collateral_num = num(collateral_amount, collateral_decimals);
        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);

        let offered_for_collateral = Math::mul(copy price_num, collateral_num);

        let hard_mc_multiplier = num(HARD_MARGIN_CALL, MARGIN_CALL_DECIMALS);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest(deal);
        let hard_mc_num = Math::mul(loan_amount_with_interest_num, hard_mc_multiplier);
        if (Math::lte(offered_for_collateral, hard_mc_num)) {
            return STATUS_HARD_MC
        };

        if (Time::days_from(deal.created_at) > deal.loan_term) {
            return STATUS_EXPIRED
        };

        STATUS_VALID_CDP
    }

    fun compute_margin_call(offered_num: Math::Num): Math::Num {
        // HMC = OFFERED_COINS * 1.3
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        Math::mul(offered_num, hard_mc_multiplier)
    }

    fun compute_ltv<Offered: copy + store, Collateral: copy + store>(
        collateral_amount: u128,
        loan_amount_num: Math::Num
    ): u64 {
        let price = Coins::get_price<Offered, Collateral>();
        let collateral_dec = Dfinance::decimals<Collateral>();

        let collateral_num = num(collateral_amount, collateral_dec);
        let price_num = num(price, EXCHANGE_RATE_DECIMALS);

        let ltv_num = Math::div(
            loan_amount_num,
            Math::mul(collateral_num, price_num)
        );
        ((Math::scale_to_decimals(ltv_num, 2) * 100) as u64)
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