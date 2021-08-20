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

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Coins::{BTC, USDT};

    use 0x1::CDP;

    fun change_max_ltv_of_the_bank(owner_acc: &signer) {
        CDP::set_bank_max_ltv<BTC, USDT>(owner_acc, 6500);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
/// aborts_with: 103
script {
    use 0x1::Coins::{BTC, USDT};

    use 0x1::CDP;

    fun cannot_change_max_ltv_of_the_bank_to_110(owner_acc: &signer) {
        CDP::set_bank_max_ltv<BTC, USDT>(owner_acc, 10000);
    }
}

/// signers: 0x103
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{BTC, USDT};

    use 0x1::CDP;

    fun add_some_more_btc_to_bank(acc: &signer) {
        let btc_amount_num = num(1, 0);
        let btc_amount = Math::scale_to_decimals(btc_amount_num, 10);
        let btc_minted = Dfinance::mint<BTC>(btc_amount);

        let bank_addr = 0x101;
        CDP::add_deposit<BTC, USDT>(acc, bank_addr, btc_minted);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Math;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    use 0x1::CDP;

    fun withdraw_some_btc_from_bank(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let btc_amount_num = num(33, 2);
        let btc_amount = Math::scale_to_decimals(btc_amount_num, 10);

        let withdrawn = CDP::withdraw_deposit<BTC, USDT>(owner_acc, btc_amount);
        Account::deposit(owner_acc, Signer::address_of(owner_acc), withdrawn);
    }
}

/// signers: 0x101, 0x102
/// current_time: 100
/// aborts_with: 105
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    fun fail_if_not_active_bank(owner_acc: &signer, borrower_acc: &signer) {
        CDP::set_is_active<BTC, USDT>(owner_acc, false);

        // ~1 BTC in USDT
        let minted_usdt = Dfinance::mint<USDT>(4460251000000);
        // 0.33 BTC
        let loan_amount_num = num(33, 2);
        let bank_addr = 0x101;
        let btc = CDP::create_deal<BTC, USDT>(
            borrower_acc,
            bank_addr,
            minted_usdt,
            loan_amount_num,
            90
        );
        Account::deposit_to_sender(borrower_acc, btc);
    }
}

/// signers: 0x101, 0x102
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math::num;
    use 0x1::Coins::{BTC, USDT};

    fun set_active_to_true_and_create_deal(owner_acc: &signer, borrower_acc: &signer) {
        CDP::set_is_active<BTC, USDT>(owner_acc, true);

        // ~1 BTC in USDT
        let minted_usdt = Dfinance::mint<USDT>(4460251000000);
        // 0.33 BTC
        let loan_amount_num = num(33, 2);

        let bank_addr = 0x101;
        let eth = CDP::create_deal<BTC, USDT>(
            borrower_acc,
            bank_addr,
            minted_usdt,
            loan_amount_num,
            90);
        Account::deposit_to_sender(borrower_acc, eth);
    }
}

/// signers: 0x101
/// price: btc_usdt 4460251000000
/// current_time: 100
script {
    use 0x1::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun set_other_parameters(owner_acc: &signer) {
        CDP::set_interest_rate<BTC, USDT>(owner_acc, 100);
        CDP::set_max_loan_term<BTC, USDT>(owner_acc, 10);
    }
}