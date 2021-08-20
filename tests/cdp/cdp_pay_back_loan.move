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

        // ~1 BTC in USDT, 44602.51 USDT
        let usdt_collateral = Dfinance::mint<USDT>(44602510000);
        // 0.65 BTC = 65% LTV
        let loan_amount_num = num(65, 2);

        let offered = CDP::create_deal(
            borrower_acc,
            bank_address,
            usdt_collateral,
            loan_amount_num,
            90
        );

        let offered_num = num(Dfinance::value(&offered), 10);
        assert(Math::scale_to_decimals(offered_num, 2) == 65, 1);  // 0.65 BTC

        Account::deposit_to_sender<BTC>(borrower_acc, offered);
    }
}

/// signers: 0x101,0x102
/// price: btc_usdt 4460251000000
/// current_time: 400
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};
    use 0x1::Math;

    fun release_collateral_after_paying_back_the_loan(owner_acc: &signer, borrower_acc: &signer) {
        let borrower_addr = Signer::address_of(borrower_acc);

        let loan_amount_num = CDP::get_loan_amount<BTC, USDT>(borrower_acc, borrower_addr);
        let loan_amount = Math::scale_to_decimals(loan_amount_num, 10);
        let minted_btc_loan = Dfinance::mint<BTC>(loan_amount);

        let collateral = CDP::pay_back<BTC, USDT>(borrower_acc, borrower_addr, minted_btc_loan);
        assert(Account::balance<USDT>(owner_acc) == 79429, 1);
        assert(Dfinance::value(&collateral) == 44602430571, 2);

        Account::deposit_to_sender(borrower_acc, collateral);
    }
}
