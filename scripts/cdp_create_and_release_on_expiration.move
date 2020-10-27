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
    use 0x1::Signer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_bank_for_0x101(lender_account: &signer) {
        // 100 * 10 ^ 10
        let num_of_xfi_available = Dfinance::mint<XFI>(2000000000000);
        let ltv = 6600;  // 66% (should always be < 0.67)
        let interest_rate = 100;  // 1%

        assert(
            !CDP2::has_offer<XFI, ETH>(Signer::address_of(lender_account)),
            108
        );
        CDP2::create_offer<XFI, ETH>(lender_account, num_of_xfi_available, ltv, interest_rate);
    }
}

// 100 * 10^8
/// price: xfi_eth 10000000000
/// signer: 0x103
/// current_time: 100
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
        assert(
            !CDP2::has_deal<XFI, ETH>(Signer::address_of(borrower_account)),
            109
        );
        let xfi_offered = CDP2::make_deal<XFI, ETH>(borrower_account, offer_address, eth_collateral, 620000000000);
        assert(Dfinance::value(&xfi_offered) == 620000000000, 501);

        Account::deposit_to_sender(
            borrower_account,
            xfi_offered
        );
    }
}

/// price: xfi_eth 10000000000
/// signer: 0x103
/// current_time: 200
script {
    use 0x1::CDP2;
    use 0x1::Account;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun return_borrowed_money_and_release_collateral(borrower_account: &signer) {
        // add 2 XFI to borrower to be able to pay for interest rate
        Account::deposit_to_sender<XFI>(borrower_account, Dfinance::mint<XFI>(20000000000));

        let collateral = CDP2::return_offered_and_release_collateral<XFI, ETH>(borrower_account);
        assert(Dfinance::value(&collateral) == 1000000000000000000, 101);

        Account::deposit_to_sender(borrower_account, collateral)
    }
}





