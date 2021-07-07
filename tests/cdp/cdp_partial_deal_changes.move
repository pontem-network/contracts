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
        let eth_amount_num = num(100, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let eth_minted = Pontem::mint<ETH>(eth_amount);
        // 66%
        let max_ltv = 7500;
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<ETH, BTC>(
            owner_acc,
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
        assert(Math::scale_to_decimals(offered_num, 0) == 65, 1);  // 65 ETH

        Account::deposit_to_sender<ETH>(borrower_acc, offered);
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

    fun borrow_5_more_eth(borrower_acc: &signer) {
        let new_loan_num = num(5, 0);
        let eth = CDP::borrow_more<ETH, BTC>(borrower_acc, new_loan_num);
        Account::deposit_to_sender<ETH>(borrower_acc, eth);

        let borrower_addr = Signer::address_of(borrower_acc);
        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 93, 1);

        let loan_amount = CDP::get_loan_amount<ETH, BTC>(borrower_addr);
        assert(Math::equals(loan_amount, num(70000178082191780805, 18)), 2);
    }
}


/// signers: 0x102
/// price: eth_btc 10000000000
/// current_time: 300
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{ETH, BTC};

    fun borrow_3_more_eth_no_new_interest_added(borrower_acc: &signer) {
        // use different representation to test for correct unpacking
        let new_loan_num = num(3000, 3);
        let eth = CDP::borrow_more<ETH, BTC>(borrower_acc, new_loan_num);
        Account::deposit_to_sender<ETH>(borrower_acc, eth);

        let borrower_addr = Signer::address_of(borrower_acc);
        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 93, 1);

        let loan_amount = CDP::get_loan_amount<ETH, BTC>(borrower_addr);
        assert(Math::equals(loan_amount, num(73000178082191780805, 18)), 2);
    }
}


/// signers: 0x102
/// price: eth_btc 8000000000
/// current_time: 400
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Pontem;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{ETH, BTC};

    fun add_more_collateral(borrower_acc: &signer) {
        let new_collateral_num = num(5, 1);  // 0.5 BTC
        let new_collateral_amount = Math::scale_to_decimals(new_collateral_num, 10);
        let new_collateral = Pontem::mint(new_collateral_amount);

        let borrower_addr = Signer::address_of(borrower_acc);
        CDP::add_collateral<ETH, BTC>(borrower_acc, borrower_addr, new_collateral);

        // without additional collateral, this 80 ETH / BTC price will give margin call
        let status = CDP::get_deal_status<ETH, BTC>(borrower_addr);
        assert(status == 93, 1);
    }
}


/// signers: 0x102
/// price: eth_btc 10000000000
/// current_time: 500
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Pontem;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{ETH, BTC};

    fun pay_back_deal_partially(borrower_acc: &signer) {
        let loan_chunk_num = num(5, 0);  // 5 ETH
        let loan_chunk_amount = Math::scale_to_decimals(loan_chunk_num, 18);
        let loan_chunk = Pontem::mint<ETH>(loan_chunk_amount);

        let borrower_addr = Signer::address_of(borrower_acc);
        CDP::pay_back_partially<ETH, BTC>(borrower_acc, borrower_addr, loan_chunk);

        // without additional collateral, this 80 ETH / BTC price will give margin call
        let loan_amount_num = CDP::get_loan_amount<ETH, BTC>(borrower_addr);
        assert(Math::equals(loan_amount_num, num(68000178082191780805, 18)), 1);
    }
}
