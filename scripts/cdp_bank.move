/// signer: 0x101
script {
    use 0x1::CDPOffer;
    use 0x1::Math;

    use 0x1::Coins::BTC;

    fun create_bank_for_signer_1(signer1: &signer) {
        let num_of_btc_available_for_cdp = 100;
        let ltv = Math::create_from_decimal(66, 2);  // 0.66 (should always be < 0.67)
        let interest_rate = Math::create_from_decimal(1, 1);  // 0.1

        CDPOffer::create<BTC>(signer1, num_of_btc_available_for_cdp, ltv, interest_rate);
    }
}

/// signer: 0x101
script {
    use 0x1::CDPOffer;
    use 0x1::Coins::{BTC};

    fun add_more_currency_to_bank(signer1: &signer) {
        let num_of_added_btc = 100;
        CDPOffer::refill<BTC>(signer1, num_of_added_btc);
    }
}

/// signer: 0x101
script {
    use 0x1::CDPOffer;
    use 0x1::Coins::{BTC};

    fun create_cdp_based_on_signer_1_cdp_offer(lender_signer: &signer) {
        CDPOffer::borrow_currency<BTC>(lender_signer, 50);
    }
}
