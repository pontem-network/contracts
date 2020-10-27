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
        let interest_rate = 1000;  // 10%

        assert(
            !CDP2::has_offer<XFI, ETH>(Signer::address_of(lender_account)),
            108
        );
        CDP2::create_offer<XFI, ETH>(lender_account, num_of_xfi_available, ltv, interest_rate);
    }
}
