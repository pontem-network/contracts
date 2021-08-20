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
            30
        );
    }
}

/// signers: 0x102
/// price: btc_usdt 4460251000000
/// current_time: 100
/// aborts_with: 103
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    fun cannot_create_deal_with_big_ltv(borrower_acc: &signer) {
        let bank_address = 0x101;

        // ~1 BTC in USDT, 44602.51 USDT, 6 signs after dot
        let usdt_collateral = Dfinance::mint<USDT>(44602510000);
        // 1 BTC = 100% LTV
        let loan_amount_num = num(1, 0);

        let offered = CDP::create_deal(
            borrower_acc, bank_address, usdt_collateral, loan_amount_num, 1);

        let offered_num = num(Dfinance::value(&offered), 18);
//        0x1::Debug::print(&Math::scale_to_decimals(copy offered_num, 18));
        assert(Math::scale_to_decimals(offered_num, 18) == 176643000, 1);

        Account::deposit_to_sender<BTC>(borrower_acc, offered);
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
        // 0.33 BTC = 33% LTV
        let loan_amount_num = num(33, 2);

        let offered = CDP::create_deal<BTC, USDT>(
            borrower_acc, bank_address, usdt_collateral, loan_amount_num, 1);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 18) == 3300000000, 1);  // 0.33 BTC

        Account::deposit_to_sender<BTC>(borrower_acc, offered);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 200
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun cannot_close_by_expiration_if_too_early(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);
    }
}


/// signers: 0x101, 0x102
/// price: btc_usdt 4460251000000
/// current_time: 2592200
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Coins::{USDT, BTC};

    fun close_deal_by_expiration(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);

        // Owner of Bank gets PRICE_OF_LOAN_IN_COLLATERAL_TOKEN = BORROWED_ETH / RATE_ETH_BTC
        // (0.33 BTC + 0.1% * (31 / 365) days * 0.33 BTC) * (BTC -> USDT price) ~= 14720.078392 USDT
        assert(Account::balance<USDT>(owner_acc) == 14720078391, 1);
        // Borrower gets remaining Collateral
        // 44602.510 USDT - 14720.078 USDT ~= 29882
        assert(Account::balance<USDT>(borrower_acc) == 29882431609, 2);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
/// aborts_with: 303
script {
    use 0x1::CDP;
    use 0x1::Coins::{USDT, BTC};

    fun deal_does_not_exist_after_closing_by_expiration(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);
    }
}