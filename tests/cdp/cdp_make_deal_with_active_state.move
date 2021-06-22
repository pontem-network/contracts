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
        // 0.10% (0010)
        let interest_rate = 10;

        CDP::create_bank<ETH, BTC>(&owner_acc, eth_minted, bank_ltv, interest_rate);
    }
}

/// signers: 0x101
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun make_bank_inactive(owner_acc: signer) {
        CDP::set_is_active<ETH, BTC>(&owner_acc, false);
    }
}


/// signers: 0x101
/// aborts_with: 105
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    fun fail_if_create_deal_on_inactive_bank(borrower_acc: signer) {
        let minted_btc = Dfinance::mint<BTC>(100);
        let bank_addr = 0x101;
        let eth = CDP::create_deal<ETH, BTC>(&borrower_acc, bank_addr, minted_btc, 1);
        Account::deposit_to_account(&borrower_acc, eth);
    }
}

/// signers: 0x101
script {
    use 0x1::CDP;
    use 0x1::Coins::{ETH, BTC};

    fun set_is_active_to_true(owner_acc: signer) {
        CDP::set_is_active<ETH, BTC>(&owner_acc, true);

    }
}

/// signers: 0x101
/// price: eth_btc 1572000000
/// current_time: 100
script {
    use 0x1::Account;
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    fun create_deal_on_active_bank(borrower_acc: signer) {
        let minted_btc = Dfinance::mint<BTC>(100);
        let bank_addr = 0x101;
        let eth = CDP::create_deal<ETH, BTC>(&borrower_acc, bank_addr, minted_btc, 1);
        Account::deposit_to_account(&borrower_acc, eth);
    }
}