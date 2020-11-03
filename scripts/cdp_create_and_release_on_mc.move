/// signers: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun register_coins(standard_account: &signer) {
        Dfinance::register_coin<ETH>(standard_account, b"eth", 18);
        Dfinance::register_coin<XFI>(standard_account, b"xfi", 10);
    }
}

/// signers: 0x101
/// price: eth_xfi 100
script {
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Signer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_bank_for_0x101(lender_account: &signer) {
        // 200 * 10 ^ 10 => 200 XFI
        let num_of_xfi_available = Dfinance::mint<XFI>(2000000000000);
        let min_ltv = 1000;  // 66% (should always be < 0.67)
        let interest_rate = 1000;  // 10%

        assert(
            !CDP::has_offer<XFI, ETH>(Signer::address_of(lender_account)),
            108
        );
        CDP::create_offer<XFI, ETH>(lender_account, num_of_xfi_available, min_ltv, interest_rate);
    }
}

/// signers: 0x102
script {
    use 0x1::CDP;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun add_more_xfi_to_bank(signer1: &signer) {
        // 100 XFI
        let num_of_xfi_added = Dfinance::mint<XFI>(1000000000000);
        let offer_address = 0x101;
        CDP::deposit_to_offer<XFI, ETH>(signer1, offer_address, num_of_xfi_added);
    }
}

// 100 XFI / ETH
/// price: eth_xfi 10000000000
/// signers: 0x103
/// current_time: 100
/// aborts_with: 1
script {
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Security;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun asserts_if_trying_to_get_an_amount_with_ltv_more_than_offer_ltv(borrower_account: &signer) {
        let offer_address = 0x101;

        // 1 ETH = 1 * 10^18 gwei
        let eth_collateral = Dfinance::mint<ETH>(1000000000000000000);

        // 70 XFI, LTV will be 70 and it's more than 62 offer ltv
        let amount_wanted = 700000000000;
        let (xfi_offered, cdp_security) = CDP::make_cdp_deal<XFI, ETH>(borrower_account, offer_address, eth_collateral, amount_wanted);
        Account::deposit(
            borrower_account,
            Signer::address_of(borrower_account),
            xfi_offered
        );
        Security::put(borrower_account, cdp_security);
    }
}

// 100 XFI / ETH
/// price: eth_xfi 10000000000
/// signers: 0x103
/// current_time: 100
script {
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Security;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_cdp_deal_for_0x103(borrower_account: &signer) {
        let offer_address = 0x101;

        // 1 ETH = 1 * 10^18 gwei
        let eth_collateral = Dfinance::mint<ETH>(1000000000000000000);
        let xfi_62 = 620000000000;
        let (xfi_offered, cdp_security) = CDP::make_cdp_deal<XFI, ETH>(borrower_account, offer_address, eth_collateral, xfi_62);
        assert(Dfinance::value(&xfi_offered) == xfi_62, 110);

        Account::deposit(
            borrower_account,
            Signer::address_of(borrower_account),
            xfi_offered
        );
        Security::put(borrower_account, cdp_security);
    }
}

// 99 * 10^8
/// price: eth_xfi 9900000000
/// signers: 0x104
/// current_time: 200
/// aborts_with: 31
script {
    use 0x1::CDP;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun do_not_release_collateral_if_hard_margin_call_does_not_occur(
        margin_call_check_signer: &signer
    ) {
        let offer_address = 0x101;
        let deal_id = 0;
        CDP::close_by_margin_call<XFI, ETH>(margin_call_check_signer, offer_address, deal_id);
    }
}


// 40 XFI / ETH
/// price: eth_xfi 4000000000
/// signers: 0x101, 0x104
/// current_time: 200
script {
    use 0x1::CDP;
    use 0x1::Account;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun release_collateral_as_hard_margin_call_achieved(
        offer_owner_signer: &signer,
        margin_call_check_signer: &signer
    ) {
        let offer_address = 0x101;
        let deal_id = 0;
        CDP::close_by_margin_call<XFI, ETH>(margin_call_check_signer, offer_address, deal_id);

        let eth_1 = 1000000000000000000;
        assert(Account::balance<ETH>(offer_owner_signer) == eth_1, 101);

        // offer still exists
        assert(CDP::has_offer<XFI, ETH>(offer_address), 102);
    }
}
