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
/// price: eth_btc 10000000000
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
        let max_ltv = 6600;
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<ETH, BTC>(
            &owner_acc,
            eth_minted,
            max_ltv,
            interest_rate,
            90
        );
    }
}

/// signers: 0x102
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, ETH};

    fun create_cdp_deal(borrower_acc: signer) {
        let bank_address = 0x101;

        // BTC collateral is 1 (= 15.72 ETH)
        let btc_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(copy btc_num, 10);

        let btc_collateral = Dfinance::mint<BTC>(btc_amount);

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 0) * num(100, 0) = 65 ETH
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(100, 0));  // 100 ETH / BTC

        let offered = CDP::create_deal(
            &borrower_acc,
            bank_address,
            btc_collateral,
            loan_amount_num,
            90);

        let offered_num = num(Dfinance::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 0) == 65, 1);  // 65 ETH

        Account::deposit_to_account<ETH>(&borrower_acc, offered);
    }
}

/// signers: 0x102
/// price: eth_btc 10000000000
/// current_time: 200
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{ETH, BTC};

    fun borrow_5_more_eth(borrower_acc: signer) {
        let new_loan_num = num(5, 0);
        let eth = CDP::borrow_more<ETH, BTC>(&borrower_acc, new_loan_num);
        Account::deposit_to_account<ETH>(&borrower_acc, eth);

        let borrower_addr = Signer::address_of(&borrower_acc);
        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 93, 1);

        let loan_amount = CDP::get_loan_amount<ETH, BTC>(borrower_addr);
        0x1::Debug::print(&loan_amount);

        assert(Math::equals(loan_amount, num(1, 0)), 2);
    }
}
