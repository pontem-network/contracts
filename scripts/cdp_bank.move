/// signer: 0x101
/// price: xfi_eth 100
script {
    use 0x1::CDPOffer;
    use 0x1::Math;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_bank_for_signer_1(signer1: &signer) {
        let num_of_btc_available_for_cdp = 100;
        let ltv = Math::create_from_decimal(66, 2);  // 0.66 (should always be < 0.67)
        let interest_rate = Math::create_from_decimal(1, 1);  // 0.1

        CDPOffer::create<XFI, ETH>(signer1, num_of_btc_available_for_cdp, ltv, interest_rate);
    }
}

/// signer: 0x101
script {
    use 0x1::CDPOffer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun add_more_currency_to_bank(signer1: &signer) {
        let num_of_added_btc = 100;
        CDPOffer::refill<XFI, ETH>(signer1, num_of_added_btc);
    }
}

/// signer: 0x101
script {
    use 0x1::CDPOffer;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_cdp_based_on_signer_1_cdp_offer(lender_signer: &signer) {
        CDPOffer::borrow_currency<XFI, ETH>(lender_signer, 50);
    }
}
