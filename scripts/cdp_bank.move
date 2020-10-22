/// signer: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun register_coins(standard_account: &signer) {
        Dfinance::register_coin<ETH>(standard_account, b"eth", 18);
        Dfinance::register_coin<XFI>(standard_account, b"xfi", 10);
    }
}

/// signer: 0x101
/// price: xfi_eth 100
script {
    use 0x1::CDP2;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_bank_for_0x101(signer1: &signer) {
        // 100 * 10 ^ 10
        let num_of_xfi_available = Dfinance::mint<XFI>(2000000000000);
        let ltv = 6600;  // 66% (should always be < 0.67)
        let interest_rate = 1000;  // 10%

        CDP2::create_offer<XFI, ETH>(signer1, num_of_xfi_available, ltv, interest_rate);
    }
}

/// signer: 0x102
script {
    use 0x1::CDP2;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun add_more_xfi_to_bank(signer1: &signer) {
        let num_of_xfi_added = Dfinance::mint<XFI>(100);
        let offer_address = 0x101;
        CDP2::deposit_amount_to_offer<XFI, ETH>(signer1, offer_address, num_of_xfi_added);
    }
}

// 100 * 10^8
/// price: xfi_eth 10000000000
/// signer: 0x103
script {
    use 0x1::CDP2;
    use 0x1::Dfinance;
    use 0x1::Account;
    use 0x1::Signer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_cdp_deal_for_0x103(borrower_account: &signer) {
        let offer_address = 0x101;
        // 1 ETH = 1 * 10^18 gwei
        let eth_collateral = Dfinance::mint<ETH>(1000000000000000000);
        let ltv = 6200;  // 62%

        let xfi_offered = CDP2::make_deal<XFI, ETH>(borrower_account, offer_address, eth_collateral, ltv);
        assert(Dfinance::value(&xfi_offered) == 620000000000, 501);

        Account::deposit(
            borrower_account,
            Signer::address_of(borrower_account),
            xfi_offered
        );

    }
}

// 99 * 10^8
/// price: xfi_eth 9900000000
/// signer: 0x101
/// signer: 0x104
script {
    use 0x1::CDP2;
    use 0x1::Account;
    use 0x1::Signer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun do_not_release_collateral_if_hard_margin_call_does_not_occur(offer_owner_signer: &signer, margin_call_check_signer: &signer) {
        let borrower_address = 0x103;
        CDP2::check_and_release_deal_if_margin_call_occurred<XFI, ETH>(margin_call_check_signer, borrower_address);

        assert(!Account::has_balance<ETH>(Signer::address_of(offer_owner_signer)), 101);
    }
}


// 66 * 10^8
/// price: xfi_eth 6600000000
/// signer: 0x101
/// signer: 0x104
script {
    use 0x1::CDP2;
    use 0x1::Account;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun release_collateral_as_hard_margin_call_achieved(offer_owner_signer: &signer, margin_call_check_signer: &signer) {
        let borrower_address = 0x103;
        CDP2::check_and_release_deal_if_margin_call_occurred<XFI, ETH>(margin_call_check_signer, borrower_address);

        assert(Account::balance<ETH>(offer_owner_signer) == 1000000000000000000, 101);
    }
}





