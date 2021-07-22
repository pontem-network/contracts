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
/// price: eth_btc 10000000000
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
        let max_ltv = 6600;
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


/// signers: 0x101
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun change_max_ltv_of_the_bank(owner_acc: &signer) {
        CDP::set_bank_max_ltv<ETH, BTC>(owner_acc, 6500);
    }
}

/// signers: 0x103
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Math;
    use 0x1::Math::num;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun add_some_more_eth_to_bank(acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let eth_amount_num = num(10, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);
        let eth_minted = Dfinance::mint<ETH>(eth_amount);

        let bank_addr = 0x101;
        CDP::add_deposit<ETH, BTC>(acc, bank_addr, eth_minted);
    }
}

/// signers: 0x101
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Math;
    use 0x1::Signer;
    use 0x1::Math::num;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun withdraw_some_eth_from_bank(owner_acc: &signer) {
        // Eth is 100 * 10^18 (18 decimal places)
        let eth_amount_num = num(10, 0);
        let eth_amount = Math::scale_to_decimals(eth_amount_num, 18);

        let withdrawn = CDP::withdraw_deposit<ETH, BTC>(owner_acc, eth_amount);
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
    use 0x1::Coins::{ETH, BTC};

    fun fail_if_not_active_bank(owner_acc: &signer, borrower_acc: &signer) {
        CDP::set_is_active<ETH, BTC>(owner_acc, false);

        let minted_btc = Dfinance::mint<BTC>(100);
        let loan_amount_num = num(1, 0);
        let bank_addr = 0x101;
        let eth = CDP::create_deal<ETH, BTC>(
            borrower_acc,
            bank_addr,
            minted_btc,
            loan_amount_num,
            90
        );
        Account::deposit_to_sender(borrower_acc, eth);
    }
}

/// signers: 0x101, 0x102
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::CDP;
    use 0x1::Math::num;
    use 0x1::Math;
    use 0x1::Coins::{ETH, BTC};

    fun set_active_to_true_and_create_deal(owner_acc: &signer, borrower_acc: &signer) {
        CDP::set_is_active<ETH, BTC>(owner_acc, true);

        let one_btc_num = num(1, 0);
        let minted_btc = Dfinance::mint<BTC>(Math::scale_to_decimals(one_btc_num, 10));  // 1 BTC = 100 ETH
        let bank_addr = 0x101;
        let loan_amount_num = num(1, 0);  // 1 ETH
        let eth = CDP::create_deal<ETH, BTC>(
            borrower_acc,
            bank_addr,
            minted_btc,
            loan_amount_num,
            90);
        Account::deposit_to_sender(borrower_acc, eth);
    }
}

/// signers: 0x101
/// price: eth_btc 10000000000
/// current_time: 100
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun set_other_parameters(owner_acc: &signer) {
        CDP::set_interest_rate<ETH, BTC>(owner_acc, 100);
        CDP::set_max_loan_term<ETH, BTC>(owner_acc, 10);
    }
}