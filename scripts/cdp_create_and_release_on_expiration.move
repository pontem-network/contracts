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
/// price: eth_xfi 10000000000
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
        CDP::create_offer<XFI, ETH>(lender_account, num_of_xfi_available, min_ltv, interest_rate, false);
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
    use 0x1::SecurityStorage;

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

        SecurityStorage::init<CDP::CDPSecurity<XFI, ETH>>(borrower_account);
        SecurityStorage::push<CDP::CDPSecurity<XFI, ETH>>(borrower_account, cdp_security);
    }
}

/// price: eth_xfi 10000000000
/// signers: 0x103
/// current_time: 200
/// aborts_with: 10
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::SecurityStorage;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun do_not_release_money_if_not_enough_xfi_to_pay_interest_rate(borrower_account: &signer) {
        let cdp_security = SecurityStorage::take<CDP::CDPSecurity<XFI, ETH>>(borrower_account, 0);
        let collateral = CDP::pay_back<XFI, ETH>(borrower_account, cdp_security);

        Account::deposit_to_sender(borrower_account, collateral)
    }
}

/// price: eth_xfi 10000000000
/// signers: 0x103
/// current_time: 200
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::SecurityStorage;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun return_borrowed_money_and_release_collateral(borrower_account: &signer) {
        // add 2 XFI to borrower to be able to pay for interest rate
        let xfi_2 = 20000000000;
        Account::deposit_to_sender<XFI>(borrower_account, Dfinance::mint<XFI>(xfi_2));

        let cdp_security = SecurityStorage::take<CDP::CDPSecurity<XFI, ETH>>(borrower_account, 0);

        let collateral = CDP::pay_back<XFI, ETH>(borrower_account, cdp_security);
        let eth_1 = 1000000000000000000;
        assert(Dfinance::value(&collateral) == eth_1, 101);

        Account::deposit_to_sender(borrower_account, collateral)
    }
}
