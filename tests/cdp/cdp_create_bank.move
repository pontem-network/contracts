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
/// price: eth_btc 1000
script {
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    use 0x1::CDP;

    fun mint_some_eth_and_create_bank_from_those_coins(owner_acc: signer) {
        let minted = Dfinance::mint<ETH>(100);
        let bank_ltv = 6000;

        CDP::create_bank<ETH, BTC>(&owner_acc, minted, bank_ltv);
    }
}

/// signers: 0x102
/// price: eth_btc 1000
script {
    use 0x1::Dfinance;
    use 0x1::CDP;

    fun create_cdp_deal(borrower_acc: signer) {
        let bank_address = 0x101;

        let btc_collateral = Dfinance::mint(10000000);
        let amount_wanted = 10000;

        CDP::create_bank()
    }
}