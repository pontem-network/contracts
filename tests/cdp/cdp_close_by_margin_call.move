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
/// aborts_with: 106
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    fun not_enough_btc_available_on_the_bank(borrower_acc: &signer) {
        let bank_address = 0x101;

        // ~1 BTC in USDT, 44602.51 USDT
        let usdt_collateral = Dfinance::mint<USDT>(44602510000);
        // 2 BTC
        let loan_amount_num = num(2, 0);

        let btc_loan = CDP::create_deal<BTC, USDT>(
            borrower_acc,
            bank_address,
            usdt_collateral,
            loan_amount_num,
            90);
        Account::deposit_to_sender<BTC>(borrower_acc, btc_loan);
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

        // ~1 BTC in USDT, 44602.51 USDT
        let usdt_collateral = Dfinance::mint<USDT>(44602510000);
        // 0.65 BTC = 65% LTV
        let loan_amount_num = num(65, 2);

        let btc_loaned = CDP::create_deal<BTC, USDT>(
            borrower_acc,
            bank_address,
            usdt_collateral,
            loan_amount_num,
            90);

        let offered_num = num(Dfinance::value(&btc_loaned), 10);
        assert(Math::scale_to_decimals(offered_num, 2) == 65, 1);  // 0.65

        Account::deposit_to_sender<BTC>(borrower_acc, btc_loaned);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun cannot_close_by_hmc_if_it_did_not_happen(owner_acc: &signer) {
        // exchange rate is 88 ETH / BTC, collateral of 1 BTC = 88 ETH, and loan margin call is 85 ETH
        let borrower_addr = 0x102;

        let status = CDP::get_deal_status<BTC, USDT>(owner_acc, borrower_addr);
        assert(status == 93, 1);

        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);
    }
}


/// signers: 0x101, 0x102
/// price: btc_usdt 5439051000000
/// current_time: 86600
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun close_deal_by_hmc(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = 0x102;

        let status = CDP::get_deal_status<BTC, USDT>(borrower_acc, borrower_addr);
        assert(status == 91, 1);

        // exchange rate is 54390 USDT -> BTC, collateral is 44600 USDT (= 0.82 BTC), and loan margin call is 0.85 BTC
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);

        // owner collateral is 44602 USDT
        // loan price is 0.65 * (1 + 0.001 * 2/365) BTC * (54390.51 BTC -> USDT) ~= 35354.02 USDT
        assert(Account::balance<USDT>(owner_acc) == 35354007788, 2);
        // Borrower gets remaining Collateral
        // 46602 USDT - 35374 USDT ~= 11054 USDT
        assert(Account::balance<USDT>(borrower_acc) == 9248502212, 3);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
/// aborts_with: 303
script {
    use 0x1::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun deal_does_not_exist_after_closing(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);
    }
}