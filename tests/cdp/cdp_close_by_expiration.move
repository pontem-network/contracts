/// signers: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    fun register_coins(std_acc: &signer) {
        Dfinance::register_coin<BTC>(std_acc, b"btc", 10);
        Dfinance::register_coin<ETH>(std_acc, b"eth", 18);
    }
}

/// signers: 0x101
/// price: eth_btc 1572000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};
    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let eth_amount_num = num(100, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let eth_minted = Dfinance::mint<ETH>(eth_amount);
        // 66%
        let bank_ltv = 6600;
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<ETH, BTC>(
            owner_acc,
            eth_minted,
            bank_ltv,
            interest_rate,
            90
        );
    }
}

/// signers: 0x102
/// price: eth_btc 1572000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun create_cdp_deal(borrower_acc: &signer) {
        let bank_address = 0x101;

        // BTC collateral is 1 (= 15.72 ETH)
        let btc_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        let btc_collateral = Dfinance::mint<BTC>(btc_amount);

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(1572, 2));  // 15.72 price
//        let amount_wanted = Math::scale_to_decimals(amount_wanted_num, 18); // 10.218 ETH

        let offered = CDP::create_deal(
            borrower_acc, bank_address, btc_collateral, loan_amount_num, 1);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 3) == 10218, 1);  // 10.218 ETH

        Account::deposit_to_sender<ETH>(borrower_acc, offered);
    }
}

/// signers: 0x101
/// price: eth_btc 1572000000
/// current_time: 200
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun cannot_close_by_expiration_if_too_early(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);
    }
}


/// signers: 0x101, 0x102
/// price: eth_btc 1172000000
/// current_time: 86600
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun close_deal_by_expiration(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);

        // Owner of Bank gets PRICE_OF_LOAN_IN_COLLATERAL_TOKEN = BORROWED_ETH / RATE_ETH_BTC
        // (10.218 ETH + 0.1% * (2 / 365) days * 10.218) / (11.72 ETH / BTC) ~= 0.87187 BTC
        assert(Account::balance<BTC>(owner_acc) == 8718477806, 90);
        // Borrower gets remaining Collateral
        // 1.00 BTC - 0.87358 BTC ~= 0.12815 BTC
        assert(Account::balance<BTC>(borrower_acc) == 1281522194, 90);
    }
}

/// signers: 0x101
/// price: eth_btc 1172000000
/// current_time: 100
/// aborts_with: 303
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun deal_does_not_exist_after_closing_by_expiration(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);
    }
}