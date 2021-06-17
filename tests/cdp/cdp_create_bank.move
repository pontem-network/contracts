/// signers: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    fun register_coins(std_acc: signer) {
        Dfinance::register_coin<BTC>(&std_acc, b"btc", 10);
        Dfinance::register_coin<ETH>(&std_acc, b"eth", 18);
    }
}

/// signers: 0x101
/// price: eth_btc 1572000000
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let eth_amount_num = num(100, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let eth_minted = Dfinance::mint<ETH>(eth_amount);
        // 66%
        let bank_ltv = 6600;

        CDP::create_bank<ETH, BTC>(&owner_acc, eth_minted, bank_ltv);
    }
}

/// signers: 0x102
/// price: eth_btc 1572000000
/// aborts_with: 106
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun not_enough_eth_available_on_the_bank(borrower_acc: signer) {
        let bank_address = 0x101;

        // BTC collateral is 1000 (= 1020 ETH > 100 ETH present in the bank)
        let btc_num = num(100, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        let btc_collateral = Dfinance::mint<BTC>(btc_amount);

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let amount_wanted_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(1572, 2));  // 15.72 price
        let amount_wanted = Math::scale_to_decimals(amount_wanted_num, 18); // 1020 ETH

        let offered = CDP::create_deal(&borrower_acc, bank_address, btc_collateral, amount_wanted);
        Account::deposit_to_account<ETH>(&borrower_acc, offered);
    }
}

/// signers: 0x102
/// price: eth_btc 1572000000
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun create_cdp_deal(borrower_acc: signer) {
        let bank_address = 0x101;

        // BTC collateral is 1 (= 10.2 ETH)
        let btc_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        let btc_collateral = Dfinance::mint<BTC>(btc_amount);

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let amount_wanted_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(1572, 2));  // 15.72 price
        let amount_wanted = Math::scale_to_decimals(amount_wanted_num, 18); // 10.218 ETH

        let offered = CDP::create_deal(&borrower_acc, bank_address, btc_collateral, amount_wanted);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 3) == 10218, 1);  // 10.218 ETH

        Account::deposit_to_account<ETH>(&borrower_acc, offered);
    }
}

/// signers: 0x101
/// price: eth_btc 1572000000
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun cannot_close_by_hmc_if_it_did_not_happen(owner_acc: signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_margin_call<ETH, BTC>(&owner_acc, borrower_addr);
    }
}


/// signers: 0x101
/// price: eth_btc 572000000
script {
    use 0x1::Account;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun close_deal_by_hmc(owner_acc: signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_margin_call<ETH, BTC>(&owner_acc, borrower_addr);

        // BTC collateral is 1000 (= 1020 ETH > 100 ETH present in the bank)
        let btc_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        assert(Account::balance<BTC>(&owner_acc) == btc_amount, 90);
    }
}

/// signers: 0x101
/// price: eth_btc 572000000
/// aborts_with: 303
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun deal_does_not_exist_after_closing(owner_acc: signer) {
        let borrower_addr = 0x102;
        CDP::close_deal_by_margin_call<ETH, BTC>(&owner_acc, borrower_addr);
    }
}