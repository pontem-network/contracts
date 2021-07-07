/// signers: 0x1
script {
    use 0x1::Pontem;
    use 0x1::Coins::{ETH, BTC};

    fun register_coins(std_acc: &signer) {
        Pontem::register_coin<BTC>(std_acc, b"btc", 10);
        Pontem::register_coin<ETH>(std_acc, b"eth", 18);
    }
}

/// signers: 0x101
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Pontem;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        // Exchange rate is 100 ETH / BTC
        let eth_amount_num = num(100, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let eth_minted = Pontem::mint<ETH>(eth_amount);
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
/// price: eth_btc 10000000000
/// current_time: 100
/// aborts_with: 106
script {
    use 0x1::Account;
    use 0x1::Pontem;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun not_enough_eth_available_on_the_bank(borrower_acc: &signer) {
        let bank_address = 0x101;

        // BTC collateral is 10 BTC (= 1000 ETH > 100 ETH present in the bank)
        let btc_num = num(10, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);
        let btc_collateral = Pontem::mint<BTC>(btc_amount);

        // Exchange rate is 100 * 10^8 (8 decimal places) = 10000000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(10, 0) * num(100, 0) =
        // 0.65 * 1000 ETH = 650 ETH > 100 ETH
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(100, 0));  // 100 ETH / BTC price

        let offered = CDP::create_deal(
            borrower_acc,
            bank_address,
            btc_collateral,
            loan_amount_num,
            90);
        Account::deposit_to_sender<ETH>(borrower_acc, offered);
    }
}

/// signers: 0x102
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Pontem;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun create_cdp_deal(borrower_acc: &signer) {
        let bank_address = 0x101;

        // BTC collateral is 1 (= 15.72 ETH)
        let btc_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        let btc_collateral = Pontem::mint<BTC>(btc_amount);

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 0) * num(100, 0) = 65 ETH
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(100, 0));  // 100 ETH / BTC

        let offered = CDP::create_deal(
            borrower_acc,
            bank_address,
            btc_collateral,
            loan_amount_num,
            90);

        let offered_num = num(Pontem::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 0) == 65, 1);  // 10.218 ETH

        Account::deposit_to_sender<ETH>(borrower_acc, offered);
    }
}

/// signers: 0x101
/// price: eth_btc 8800000000
/// current_time: 100
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun cannot_close_by_hmc_if_it_did_not_happen(owner_acc: &signer) {
        // exchange rate is 88 ETH / BTC, collateral of 1 BTC = 88 ETH, and loan margin call is 85 ETH
        let borrower_addr = 0x102;

        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 93, 1);

        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);
    }
}


/// signers: 0x101, 0x102
/// price: eth_btc 8000000000
/// current_time: 86600
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun close_deal_by_hmc(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = 0x102;

        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 91, 1);

        // exchange rate is 80 ETH / BTC, collateral of 1 BTC = 80 ETH, and loan margin call is 85 ETH
        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);

        // owner collateral is (65 ETH + two days interest) in collateral ~= 67 ETH in collateral ~= 0.81 BTC
        // borrower collateral is 13 ETH in collateral ~= 0.19 BTC
        assert(Account::balance<BTC>(owner_acc) == 8125044520, 2);
        // Borrower gets remaining Collateral
        // 1.00 BTC - 0.87358 BTC ~= 0.12815 BTC
        assert(Account::balance<BTC>(borrower_acc) == 1874955480, 3);
    }
}

/// signers: 0x101
/// price: eth_btc 1172000000
/// current_time: 100
/// aborts_with: 303
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun deal_does_not_exist_after_closing(owner_acc: &signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_termination_status<ETH, BTC>(owner_acc, borrower_addr);
    }
}