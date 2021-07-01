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

    const GLOBAL_MAX_LTV: u64 = 8500;  // 85.00%
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

    resource struct Bank<Offered: copyable, Collateral: copyable> {
        deposit: Dfinance::T<Offered>,

        /// Loan-to-Value ratio: [0, 6600] (2 signs after comma)
        max_ltv: u64,
        /// loan interest rate: [0, 10000] (2 signs after comma)
        interest_rate_per_year: u64,
        /// whether this bank can be used for new cdp deals
        is_active: bool,

        max_loan_term_in_days: u64,
        active_deals_count: u64,
        next_deal_id: u64,
    }

    public fun create_bank<Offered: copyable, Collateral: copyable>(
        owner_acc: &signer,
        deposit: Dfinance::T<Offered>,
        max_ltv: u64,
        interest_rate_per_year: u64,
        max_loan_term_in_days: u64,
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
                max_loan_term_in_days,
                active_deals_count: 0,
                next_deal_id: 1
            };
        move_to(owner_acc, bank);

        Event::emit(
            owner_acc,
            BankCreatedEvent<Offered, Collateral> {
                owner: Signer::address_of(owner_acc),
                deposit_amount,
                max_ltv,
                interest_rate_per_year,
                max_loan_term_in_days
            });
    }

    public fun add_deposit<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        bank_addr: address,
        deposit: Dfinance::T<Offered>,
    ) acquires Bank {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        Dfinance::deposit(&mut bank.deposit, deposit);
        Event::emit(
            acc,
            BankUpdatedDepositAmountEvent<Offered, Collateral> {
                owner: bank_addr,
                new_deposit_amount: Dfinance::value(&bank.deposit)
            });
    }

    public fun withdraw_deposit<Offered: copyable, Collateral: copyable>(
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
        let withdrawn = Dfinance::withdraw(&mut bank.deposit, amount);
        Event::emit(
            owner_acc,
            BankUpdatedDepositAmountEvent<Offered, Collateral> {
                owner: bank_addr,
                new_deposit_amount: Dfinance::value(&bank.deposit)
            });
        withdrawn
    }

    public fun set_interest_rate<Offered: copyable, Collateral: copyable>(
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
        bank.interest_rate_per_year = interest_rate_per_year;
        Event::emit(
            owner_acc,
            BankUpdatedInterestRateEvent<Offered, Collateral> {
                owner: bank_addr,
                new_interest_rate: interest_rate_per_year
            })
    }

    public fun set_max_loan_term<Offered: copyable, Collateral: copyable>(
        owner_acc: &signer,
        max_loan_term_in_days: u64,
    ) acquires Bank {
        assert(max_loan_term_in_days > 0, ERR_INCORRECT_LOAN_TERM);
        let bank_addr = Signer::address_of(owner_acc);
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        bank.max_loan_term_in_days = max_loan_term_in_days;
        Event::emit(
            owner_acc,
            BankUpdatedLoanTermEvent<Offered, Collateral> {
                owner: bank_addr,
                new_max_loan_term: max_loan_term_in_days,
            });
    }

    public fun set_is_active<Offered: copyable, Collateral: copyable>(
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

    resource struct Deal<Offered: copyable, Collateral: copyable> {
        deal_id: u64,
        bank_owner_addr: address,
        loan_amount_num: Math::Num,
        collateral: Dfinance::T<Collateral>,
        created_at: u64,
        // 0 means that created_at should be used
        collect_interest_rate_from: u64,
        loan_term_in_days: u64,
        interest_rate_per_year: u64,
    }

    public fun create_deal<Offered: copyable, Collateral: copyable>(
        borrower_acc: &signer,
        bank_addr: address,
        collateral: Dfinance::T<Collateral>,
        loan_amount_num: Math::Num,
        loan_term_in_days: u64,
    ): Dfinance::T<Offered> acquires Bank {
        assert(
            exists<Bank<Offered, Collateral>>(bank_addr),
            ERR_BANK_DOES_NOT_EXIST
        );

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_addr);
        assert(bank.is_active, ERR_BANK_IS_NOT_ACTIVE);
        assert(loan_term_in_days <= bank.max_loan_term_in_days, ERR_INCORRECT_LOAN_TERM);

        let offered_decimals = Dfinance::decimals<Offered>();
        let loan_amount = Math::scale_to_decimals(copy loan_amount_num, offered_decimals);
        assert(loan_amount > 0, ERR_ZERO_AMOUNT);
        assert(
            Dfinance::value(&bank.deposit) >= loan_amount,
            ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS
        );

        let collateral_amount = Dfinance::value(&collateral);
        assert(collateral_amount > 0, ERR_ZERO_COLLATERAL);

        let interest_rate_per_year = bank.interest_rate_per_year;
        let deal = Deal<Offered, Collateral> {
            deal_id: bank.next_deal_id,
            bank_owner_addr: bank_addr,
            collateral,
            loan_amount_num: copy loan_amount_num,
            created_at: Time::now(),
            collect_interest_rate_from: 0,
            interest_rate_per_year,
            loan_term_in_days,
        };
        let deal_id = deal.deal_id;

        let loan_amount_with_one_day_interest = compute_loan_amount_with_interest(&deal);
        let deal_ltv =
            compute_ltv<Offered, Collateral>(
                collateral_amount,
                loan_amount_with_one_day_interest
            );
        assert(deal_ltv <= bank.max_ltv, ERR_INCORRECT_LTV);

        move_to(borrower_acc, deal);
        bank.active_deals_count = bank.active_deals_count + 1;
        bank.next_deal_id = bank.next_deal_id + 1;

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, loan_amount);
        Event::emit(
            borrower_acc,
            DealCreatedEvent<Offered, Collateral> {
                borrower_addr: Signer::address_of(borrower_acc),
                bank_owner_addr: bank_addr,
                deal_id,
                loan_amount_num,
                collateral_amount,
                loan_term_in_days,
                interest_rate_per_year,
            });
        offered
    }

    public fun borrow_more<Offered: copyable, Collateral: copyable>(
        borrower_acc: &signer,
        new_loan_amount_num: Math::Num
    ): Dfinance::T<Offered> acquires Deal, Bank {
        let borrower_addr = Signer::address_of(borrower_acc);
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let bank = borrow_global_mut<Bank<Offered, Collateral>>(deal.bank_owner_addr);

        let offered_decimals = Dfinance::decimals<Offered>();
        let new_loan_amount = Math::scale_to_decimals(copy new_loan_amount_num, offered_decimals);
        assert(new_loan_amount > 0, ERR_ZERO_AMOUNT);
        assert(
            Dfinance::value(&bank.deposit) >= new_loan_amount,
            ERR_BANK_DOES_NOT_HAVE_ENOUGH_COINS
        );
        let collateral_amount = Dfinance::value(&deal.collateral);

        let existing_loan_amount_num = compute_loan_amount_with_interest(deal);
        deal.collect_interest_rate_from = Time::now();
        deal.loan_amount_num = Math::add(existing_loan_amount_num, new_loan_amount_num);

        let new_loan_amount_num = compute_loan_amount_with_interest(deal);
        let new_deal_ltv = compute_ltv<Offered, Collateral>(collateral_amount, new_loan_amount_num);
        assert(new_deal_ltv <= bank.max_ltv, ERR_INCORRECT_LTV);

        let offered = Dfinance::withdraw<Offered>(&mut bank.deposit, new_loan_amount);
        Event::emit(
            borrower_acc,
            DealBorrowedMoreEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr: deal.bank_owner_addr,
                deal_id: deal.deal_id,
                new_loan_amount,
            });
        offered
    }

    public fun pay_back_partially<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        borrower_addr: address,
        offered: Dfinance::T<Offered>
    ) acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest(deal);
        let bank_owner_addr = deal.bank_owner_addr;

        let loan_amount_with_interest = Math::scale_to_decimals(
            copy loan_amount_with_interest_num, Dfinance::decimals<Offered>());

        let offered_amount = Dfinance::value(&offered);
        assert(
            offered_amount < loan_amount_with_interest,
            ERR_INVALID_PAYBACK_AMOUNT
        );

        let offered_decimals = Dfinance::decimals<Offered>();
        let offered_num = num(offered_amount, offered_decimals);

        let new_loan_amount_num = Math::sub(loan_amount_with_interest_num, offered_num);
        deal.loan_amount_num = new_loan_amount_num;
        deal.collect_interest_rate_from = Time::now();

        Account::deposit(acc, bank_owner_addr, offered);
        Event::emit(
            acc,
            DealPartiallyRepaidEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr,
                deal_id: deal.deal_id,
                repaid_loan_amount: offered_amount,
            });
    }

    public fun add_collateral<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        borrower_addr: address,
        collateral: Dfinance::T<Collateral>
    ) acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let collateral_amount = Dfinance::value(&collateral);
        Dfinance::deposit(&mut deal.collateral, collateral);
        Event::emit(
            acc,
            DealCollateralAddedEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr: deal.bank_owner_addr,
                deal_id: deal.deal_id,
                collateral_added_amount: collateral_amount,
            });
    }

    public fun collect_interest_rate<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        borrower_addr: address,
    ): Dfinance::T<Collateral> acquires Deal {
        assert(
            exists<Deal<Offered, Collateral>>(borrower_addr),
            ERR_DEAL_DOES_NOT_EXIST
        );

        let deal = borrow_global_mut<Deal<Offered, Collateral>>(borrower_addr);
        let loan_amount_num = *&deal.loan_amount_num;
        let interest_multiplier = compute_interest_rate_multiplier(deal);

        let loan_interest_num = Math::mul(loan_amount_num, interest_multiplier);
        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);

        let loan_interest_in_collateral_num = Math::div(loan_interest_num, price_num);
        let collateral_decimals = Dfinance::decimals<Collateral>();
        let loan_interest_in_collateral_amount = Math::scale_to_decimals(
            loan_interest_in_collateral_num,
            collateral_decimals);

        let interest_collateral = Dfinance::withdraw(
            &mut deal.collateral, loan_interest_in_collateral_amount);
        deal.collect_interest_rate_from = Time::now();
        Event::emit(
            acc,
            DealInterestCollectedEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr: deal.bank_owner_addr,
                deal_id: deal.deal_id,
                interest_collateral_amount: Dfinance::value(&interest_collateral)
            }
        );
        interest_collateral
    }

    public fun close_deal_by_termination_status<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        borrower_addr: address
    ) acquires Deal, Bank {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal_status = get_deal_status<Offered, Collateral>(borrower_addr);
        assert(
            deal_status != STATUS_VALID_CDP,
            ERR_HARD_MC_HAS_NOT_OCCURRED_OR_NOT_EXPIRED
        );

        let deal = move_from<Deal<Offered, Collateral>>(borrower_addr);
        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest<Offered, Collateral>(&deal);
        let Deal {
            deal_id,
            bank_owner_addr,
            collateral,
            loan_amount_num,
            created_at: _,
            collect_interest_rate_from: _,
            loan_term_in_days: _,
            interest_rate_per_year: _,
        } = deal;

        let bank = borrow_global_mut<Bank<Offered, Collateral>>(bank_owner_addr);
        bank.active_deals_count = bank.active_deals_count - 1;

        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collateral_num = num(Dfinance::value(&collateral), collateral_decimals);
        let collateral_in_offered_num =
            Math::mul(copy price_num, collateral_num);

        let borrower_collateral_amount;
        let owner_collateral_amount;
        if (math_lt(copy loan_amount_with_interest_num, collateral_in_offered_num)) {
            let owner_collateral_num =
                Math::div(loan_amount_with_interest_num, price_num);
            owner_collateral_amount =
                Math::scale_to_decimals(owner_collateral_num, collateral_decimals);
            // pay bank with collateral amount of the loan
            let owner_collateral = Dfinance::withdraw(&mut collateral, owner_collateral_amount);
            Account::deposit(acc, bank_owner_addr, owner_collateral);
            // set variables for events
            borrower_collateral_amount = Dfinance::value(&collateral);
            // send rest of the collateral back to borrower
            Account::deposit(acc, borrower_addr, collateral);
        } else {
            // not enough collateral to cover the loan, just send all collateral to bank
            owner_collateral_amount = Dfinance::value(&collateral);
            borrower_collateral_amount = 0;
            Account::deposit(acc, bank_owner_addr, collateral);
        };
        Event::emit(
            acc,
            DealTerminatedEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr,
                deal_id,
                loan_amount_num,
                owner_collateral_amount,
                borrower_collateral_amount,
                termination_status: deal_status
            })
    }

    public fun pay_back<Offered: copyable, Collateral: copyable>(
        acc: &signer,
        borrower_addr: address,
        offered: Dfinance::T<Offered>,
    ): Dfinance::T<Collateral> acquires Deal {
        assert(exists<Deal<Offered, Collateral>>(borrower_addr), ERR_DEAL_DOES_NOT_EXIST);

        let deal = move_from<Deal<Offered, Collateral>>(borrower_addr);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest<Offered, Collateral>(&deal);
        let offered_decimals = Dfinance::decimals<Offered>();
        let loan_amount_with_interest = Math::scale_to_decimals(
            copy loan_amount_with_interest_num, offered_decimals);
        assert(
            Dfinance::value(&offered) == loan_amount_with_interest,
            ERR_INVALID_PAYBACK_AMOUNT
        );
        let Deal {
            deal_id,
            bank_owner_addr,
            collateral,
            loan_amount_num: _,
            created_at: _,
            collect_interest_rate_from: _,
            loan_term_in_days: _,
            interest_rate_per_year: _,
        } = deal;

        Account::deposit(acc, bank_owner_addr, offered);
        Event::emit(
            acc,
            DealPaidBackEvent<Offered, Collateral> {
                borrower_addr,
                bank_owner_addr,
                deal_id,
                loan_amount_with_interest_num,
                collateral_amount: Dfinance::value(&collateral),
            });
        collateral
    }

    public fun get_loan_amount<Offered: copyable, Collateral: copyable>(
        borrower_addr: address
    ): Math::Num acquires Deal {
        let deal = borrow_global<Deal<Offered, Collateral>>(borrower_addr);
        compute_loan_amount_with_interest(deal)
    }

    public fun get_deal_status<Offered: copyable, Collateral: copyable>(
        borrower_addr: address
    ): u8 acquires Deal {
        let deal = borrow_global<Deal<Offered, Collateral>>(borrower_addr);

        let collateral_amount = Dfinance::value(&deal.collateral);
        let collateral_decimals = Dfinance::decimals<Collateral>();
        let collateral_num = num(collateral_amount, collateral_decimals);
        let price_num = num(Coins::get_price<Offered, Collateral>(), EXCHANGE_RATE_DECIMALS);

        let offered_for_collateral = Math::mul(copy price_num, collateral_num);

        let hard_mc_multiplier = num(HARD_MARGIN_CALL, MARGIN_CALL_DECIMALS);
        let loan_amount_with_interest_num = compute_loan_amount_with_interest(deal);
        let hard_mc_num = Math::mul(loan_amount_with_interest_num, hard_mc_multiplier);
        if (Math::scale_to_decimals(offered_for_collateral, 18)
            <= Math::scale_to_decimals(hard_mc_num, 18)) {
            return STATUS_HARD_MC
        };

        if (Time::days_from(deal.created_at) > deal.loan_term_in_days) {
            return STATUS_EXPIRED
        };

        STATUS_VALID_CDP
    }

    fun compute_loan_amount_with_interest<Offered: copyable, Collateral: copyable>(
        deal: &Deal<Offered, Collateral>,
    ): Math::Num {
        let interest_multiplier = compute_interest_rate_multiplier(deal);
        let loan_amount_num = *&deal.loan_amount_num;
        let offered_with_interest_num =
            Math::add(
                copy loan_amount_num,
                Math::mul(loan_amount_num, interest_multiplier)
            );
        offered_with_interest_num
    }

    fun compute_interest_rate_multiplier<Offered: copyable, Collateral: copyable>(
        deal: &Deal<Offered, Collateral>
    ): Math::Num {
        let zero_day_interest_collected = deal.collect_interest_rate_from != 0;
        let collect_interest_rate_from =
            if (zero_day_interest_collected) deal.collect_interest_rate_from else deal.created_at;
        let days_passed =
            Time::days_from(collect_interest_rate_from) + (if (!zero_day_interest_collected) 1 else 0);
        let days_passed_num = num((days_passed as u128), 0);
        let interest_rate_num = num((deal.interest_rate_per_year as u128), INTEREST_RATE_DECIMALS);
        let days_in_year = num(365, 0);
        Math::div(Math::mul(days_passed_num, interest_rate_num), days_in_year)
    }

    fun compute_margin_call(offered_num: Math::Num): Math::Num {
        // HMC = OFFERED_COINS * 1.3
        let hard_mc_multiplier = num(HARD_MARGIN_CALL, 2);
        Math::mul(offered_num, hard_mc_multiplier)
    }

    fun compute_ltv<Offered: copyable, Collateral: copyable>(
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

    fun math_lt(l: Math::Num, r: Math::Num): bool {
        Math::scale_to_decimals(l, 18) < Math::scale_to_decimals(r, 18)
    }

    struct BankCreatedEvent<Offered: copyable, Collateral: copyable> {
        owner: address,
        deposit_amount: u128,
        max_ltv: u64,
        interest_rate_per_year: u64,
        max_loan_term_in_days: u64,
    }

    struct BankUpdatedDepositAmountEvent<Offered: copyable, Collateral: copyable> {
        owner: address,
        new_deposit_amount: u128,
    }

    struct BankUpdatedInterestRateEvent<Offered: copyable, Collateral: copyable> {
        owner: address,
        new_interest_rate: u64,
    }

    struct BankUpdatedLoanTermEvent<Offered: copyable, Collateral: copyable> {
        owner: address,
        new_max_loan_term: u64,
    }

    struct BankChangeActiveStatus<Offered: copyable, Collateral: copyable> {
        owner: address,
        is_active: bool
    }

    struct DealCreatedEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        loan_amount_num: Math::Num,
        collateral_amount: u128,
        loan_term_in_days: u64,
        interest_rate_per_year: u64,
    }

    struct DealBorrowedMoreEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        new_loan_amount: u128,
    }

    struct DealPartiallyRepaidEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        repaid_loan_amount: u128,
    }

    struct DealCollateralAddedEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        collateral_added_amount: u128
    }

    struct DealInterestCollectedEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        interest_collateral_amount: u128,
    }

    struct DealTerminatedEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        loan_amount_num: Math::Num,
        owner_collateral_amount: u128,
        borrower_collateral_amount: u128,
        termination_status: u8,
    }

    struct DealPaidBackEvent<Offered: copyable, Collateral: copyable> {
        borrower_addr: address,
        bank_owner_addr: address,
        deal_id: u64,
        loan_amount_with_interest_num: Math::Num,
        collateral_amount: u128,
    }
}
}