/// signers: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};

    fun register_coins(std_acc: &signer) {
        Dfinance::register_coin<BTC>(std_acc, b"btc", 10);
        Dfinance::register_coin<USDT>(std_acc, b"usdt", 6);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};
    use 0x1::CDP;

    fun mint_some_btc_and_create_bank_from_those_coins(owner_acc: &signer) {
        let btc_amount_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(btc_amount_num, 10);

        let btc_minted = Dfinance::mint<BTC>(btc_amount);
        // 66%
        let bank_ltv = 6600;
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<BTC, USDT>(
            owner_acc,
            btc_minted,
            bank_ltv,
            interest_rate,
            90
        );
    }
}

/// signers: 0x102
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    fun create_cdp_deal(borrower_acc: &signer) {
        let bank_address = 0x101;

        // ~1 BTC in USDT, 44602.51 USDT, 6 signs after dot
        let usdt_collateral = Dfinance::mint<USDT>(44602510000);
        // 0.33 BTC = 33% LTV
        let loan_amount_num = num(33, 2);

        let loaned_btc = CDP::create_deal<BTC, USDT>(
            borrower_acc,
            bank_address,
            usdt_collateral,
            loan_amount_num,
            90);

        let loaned_btc_num = num(Dfinance::value(&loaned_btc), 10);
        assert(Math::scale_to_decimals(loaned_btc_num, 2) == 33, 1);  // 0.33 BTC

        Account::deposit_to_sender<BTC>(borrower_acc, loaned_btc);
    }
}

/// signers: 0x101,0x102
/// price: btc_usdt 4460251000000
/// current_time: 200
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{BTC, USDT};

    fun borrow_0_25_more_btc(owner_acc: &signer, borrower_acc: &signer) {
        // 0.25 BTC
        let new_loan_num = num(25, 2);
        let more_loaned_btc = CDP::borrow_more<BTC, USDT>(borrower_acc, new_loan_num);
        Account::deposit_to_sender<BTC>(borrower_acc, more_loaned_btc);

        let borrower_addr = Signer::address_of(borrower_acc);
        let status = CDP::get_deal_status<BTC, USDT>(borrower_acc, borrower_addr);
        assert(status == 93, 1);

        let loan_amount = CDP::get_loan_amount<BTC, USDT>(borrower_acc, borrower_addr);
        assert(Math::equals(loan_amount, num(58, 2)), 2);

        assert(Account::balance<USDT>(owner_acc) == 40325, 3);
    }
}


/// signers: 0x101,0x102
/// price: btc_usdt 4460251000000
/// current_time: 400
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{BTC, USDT};

    fun borrow_0_02_more_btc_no_new_interest_added(owner_acc: &signer, borrower_acc: &signer) {
        // use different representation to test for correct unpacking
        // 0.02 BTC
        let new_loan_num = num(2, 2);
        let new_loan_btc = CDP::borrow_more<BTC, USDT>(borrower_acc, new_loan_num);
        Account::deposit_to_sender<BTC>(borrower_acc, new_loan_btc);

        let borrower_addr = Signer::address_of(borrower_acc);
        let status = CDP::get_deal_status<BTC, USDT>(borrower_acc, borrower_addr);
        assert(status == 93, 1);

        let loan_amount = CDP::get_loan_amount<BTC, USDT>(borrower_acc, borrower_addr);
        assert(Math::equals(loan_amount, num(60, 2)), 2);

        assert(Account::balance<USDT>(owner_acc) == 40325, 3);
    }
}


/// signers: 0x101,0x102
/// price: btc_usdt 4460251000000
/// current_time: 86800
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};

    fun add_more_collateral(owner_acc: &signer, borrower_acc: &signer) {
        // ~0.5 BTC in USDT, 22302.51 USDT, 6 signs after dot
        let additional_usdt_collateral = Dfinance::mint<USDT>(22302510000);

        let borrower_addr = Signer::address_of(borrower_acc);
        CDP::add_collateral<BTC, USDT>(borrower_acc, borrower_addr, additional_usdt_collateral);

        // without additional collateral, this 80 ETH / BTC price will give margin call
        let status = CDP::get_deal_status<BTC, USDT>(borrower_acc, borrower_addr);
        assert(status == 93, 1);

        assert(Account::balance<USDT>(owner_acc) == 113644, 3);
    }
}

/// signers: 0x102
/// price: btc_usdt 4460251000000
/// current_time: 86800
/// aborts_with: 103
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};

    fun cannot_withdraw_collateral_if_ltv_is_too_big(borrower_acc: &signer) {
        // 44602 USDT = 1 BTC
        let withdrawn_collateral_amount = 44602510000;

        let borrower_addr = Signer::address_of(borrower_acc);
        let withdrawn_collateral =
            CDP::get_collateral<BTC, USDT>(borrower_acc, borrower_addr, withdrawn_collateral_amount);
        assert(Dfinance::value(&withdrawn_collateral) == withdrawn_collateral_amount, 1);

        Account::deposit_to_sender(borrower_acc, withdrawn_collateral);
    }
}


/// signers: 0x102
/// price: btc_usdt 4460251000000
/// current_time: 86800
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};

    fun withdraw_collateral(borrower_acc: &signer) {
        // 22302 USDT = 0.5 BTC
        let withdrawn_collateral_amount = 22302510000;

        let borrower_addr = Signer::address_of(borrower_acc);
        let withdrawn_collateral =
            CDP::get_collateral<BTC, USDT>(borrower_acc, borrower_addr, withdrawn_collateral_amount);
        assert(Dfinance::value(&withdrawn_collateral) == withdrawn_collateral_amount, 1);

        Account::deposit_to_sender(borrower_acc, withdrawn_collateral);
    }
}


/// signers: 0x102
/// price: btc_usdt 4460251000000
/// current_time: 86800
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{BTC, USDT};

    fun pay_back_deal_partially(borrower_acc: &signer) {
        // 0.5 BTC
        let loan_chunk_btc_num = num(5, 1);
        let loan_chunk_btc_amount = Math::scale_to_decimals(loan_chunk_btc_num, 10);
        let loan_chunk = Dfinance::mint<BTC>(loan_chunk_btc_amount);

        let borrower_addr = Signer::address_of(borrower_acc);
        CDP::pay_back_partially<BTC, USDT>(borrower_acc, borrower_addr, loan_chunk);

        // without additional collateral, this 80 ETH / BTC price will give margin call
        let loan_amount_num = CDP::get_loan_amount<BTC, USDT>(borrower_acc, borrower_addr);
        assert(Math::equals(loan_amount_num, num(1, 1)), 1);
    }
}
