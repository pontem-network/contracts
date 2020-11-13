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
        CDP::create_offer_without_dro<XFI, ETH>(
            lender_account,
            num_of_xfi_available,
            min_ltv,
            interest_rate,
            10000000000 // seconds duration
);
    }
}

// 100 XFI / ETH
/// price: eth_xfi 10000000000
/// signers: 0x103
/// current_time: 100
script {
    use 0x1::CDP::{Self, CDP};
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
        let (xfi_offered, cdp_security) = CDP::make_deal<XFI, ETH>(borrower_account, offer_address, eth_collateral, xfi_62);
        assert(Dfinance::value(&xfi_offered) == xfi_62, 110);

        Account::deposit(
            borrower_account,
            Signer::address_of(borrower_account),
            xfi_offered
        );

        SecurityStorage::init<CDP<XFI, ETH>>(borrower_account);
        SecurityStorage::push<CDP<XFI, ETH>>(borrower_account, cdp_security);
    }
}


// 100 XFI / ETH, 0.5 of deal duration
/// price: eth_xfi 10000000000
/// signers: 0x101, 0x104
/// current_time: 5000000000
/// aborts_with: 302
script {
    use 0x1::CDP;
    use 0x1::Account;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun do_not_release_collateral_if_deal_if_not_yet_expired(
        offer_owner_signer: &signer,
        margin_call_check_signer: &signer
    ) {
        let offer_address = 0x101;
        let deal_id = 0;
        CDP::close_by_status<XFI, ETH>(margin_call_check_signer, offer_address, deal_id);

        let eth_1 = 1000000000000000000;
        assert(Account::balance<ETH>(offer_owner_signer) == eth_1, 101);

        // offer still exists
        assert(CDP::has_offer<XFI, ETH>(offer_address), 102);
    }
}

// 100 XFI / ETH, 1.2 of deal duration
/// price: eth_xfi 10000000000
/// signers: 0x101, 0x104
/// current_time: 12000000000
script {
    use 0x1::CDP;
    use 0x1::Account;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun do_not_release_collateral_if_deal_if_not_yet_expired(
        offer_owner_signer: &signer,
        margin_call_check_signer: &signer
    ) {
        let offer_address = 0x101;
        let deal_id = 0;
        CDP::close_by_status<XFI, ETH>(margin_call_check_signer, offer_address, deal_id);

        let eth_1 = 1000000000000000000;
        assert(Account::balance<ETH>(offer_owner_signer) == eth_1, 101);

        // offer still exists
        assert(CDP::has_offer<XFI, ETH>(offer_address), 102);
    }
}
