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
/// price: eth_btc 1572000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Pontem;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let eth_amount_num = num(100, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let eth_minted = Pontem::mint<ETH>(eth_amount);
        // 66%
        let bank_ltv = 6600;
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<ETH, BTC>(
            owner_acc, eth_minted, bank_ltv, interest_rate, 90);
    }
}

/// signers: 0x102
/// price: eth_btc 1572000000
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

        // Exchange rate is 15.72 * 10^8 (8 decimal places) = 1572000000

        // LTV = (Offered / (Collateral * Price)) * 100%
        // Offered = LTV * Collateral * Price / 100%
        // num(6500, 2) * num(1, 10) * num(1572, 2) =
        let loan_amount_num = Math::mul(
            Math::mul(
                num(65, 2), // 0.65
                btc_num),
            num(1572, 2));  // 15.72 price
        let offered = CDP::create_deal(
            borrower_acc,
            bank_address,
            btc_collateral,
            loan_amount_num,
            90
        );

        let offered_num = num(Pontem::value(&offered), 18);
        assert(Math::scale_to_decimals(offered_num, 3) == 10218, 1);  // 10.218 ETH

        Account::deposit_to_sender<ETH>(borrower_acc, offered);
    }
}

/// signers: 0x102
/// price: eth_btc 1372000000
/// current_time: 400
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Pontem;
    use 0x1::Coins::{ETH, BTC};
    use 0x1::Math;
    use 0x1::Math::num;

    fun release_collateral_after_paying_back_the_loan(borrower_acc: &signer) {
        let borrower_addr = Signer::address_of(borrower_acc);

        let loan_amount_num = CDP::get_loan_amount<ETH, BTC>(borrower_addr);
        let loan_amount = Math::scale_to_decimals(loan_amount_num, 18);
        let minted_eth_loan = Pontem::mint<ETH>(loan_amount);

        let collateral = CDP::pay_back<ETH, BTC>(borrower_acc, borrower_addr, minted_eth_loan);
        let expected_collateral_btc_num = num(1, 0);
        assert(
            Pontem::value(&collateral) == Math::scale_to_decimals(expected_collateral_btc_num, 10),
            10
        );
        Account::deposit_to_sender(borrower_acc, collateral);
    }
}
