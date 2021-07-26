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
/// price: btc_usdt 3099
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};
    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let btc_amount_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(btc_amount_num, 18);

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
/// price: btc_usdt 3099
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

        // BTC collateral is 1 (= 15.72 ETH)
        let usdt_num = num(250, 0);
        let usdt_amount = Math::scale_to_decimals(copy usdt_num, 6);

        // 250 USDT
        // 0.001 BTC
        // 0.00003099
        let usdt_collateral = Dfinance::mint<USDT>(usdt_amount);

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let loan_amount_num = Math::mul(
            Math::mul(
                num(228, 2), // 0.65
                usdt_num),
            num(3099, 8));

        let offered = CDP::create_deal(
            borrower_acc, bank_address, usdt_collateral, loan_amount_num, 1);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 18) == 50358750, 1);  // 10.218 ETH

        Account::deposit_to_sender<BTC>(borrower_acc, offered);
    }
}

/// signers: 0x102
/// price: btc_usdt 3099
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

        // BTC collateral is 1 (= 15.72 ETH)
        let usdt_num = num(250, 0);
        let usdt_amount = Math::scale_to_decimals(copy usdt_num, 6);

        // 250 USDT
        // 0.001 BTC
        // 0.00003099
        let usdt_collateral = Dfinance::mint<USDT>(usdt_amount);

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                usdt_num),
            num(3099, 8));

        let offered = CDP::create_deal<BTC, USDT>(
            borrower_acc, bank_address, usdt_collateral, loan_amount_num, 1);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 18) == 50358750, 1);  // 10.218 ETH

        Account::deposit_to_sender<BTC>(borrower_acc, offered);
    }
}

/// signers: 0x101
/// price: btc_usdt 3099
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
/// price: btc_usdt 2099
/// current_time: 86600
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Coins::{USDT, BTC};

    fun close_deal_by_expiration(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<BTC, USDT>(owner_acc, borrower_addr);

        // Owner of Bank gets PRICE_OF_LOAN_IN_COLLATERAL_TOKEN = BORROWED_ETH / RATE_ETH_BTC
        // (10.218 ETH + 0.1% * (2 / 365) days * 10.218) / (11.72 ETH / BTC) ~= 0.87187 BTC
        assert(Account::balance<USDT>(owner_acc) == 239919132, 90);
        // Borrower gets remaining Collateral
        // 1.00 BTC - 0.87358 BTC ~= 0.12815 BTC
        assert(Account::balance<USDT>(borrower_acc) == 10080868, 90);
    }
}

/// signers: 0x101
/// price: btc_usdt 2099
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