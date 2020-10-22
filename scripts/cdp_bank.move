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
    use 0x1::CDPOffer;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_bank_for_signer_1(signer1: &signer) {
        let num_of_xfi_available = Dfinance::mint<XFI>(100);
        let ltv = 6600;  // 66% (should always be < 0.67)
        let interest_rate = 1000;  // 10%

        CDPOffer::create<XFI, ETH>(signer1, num_of_xfi_available, ltv, interest_rate);
    }
}

/// signer: 0x102
script {
    use 0x1::CDPOffer;
    use 0x1::Dfinance;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun add_more_xfi_to_bank(signer1: &signer) {
        let num_of_xfi_added = Dfinance::mint<XFI>(100);
        let bank_address = 0x101;
        CDPOffer::deposit_amount<XFI, ETH>(signer1, bank_address, num_of_xfi_added);
    }
}

/// signer: 0x101
script {
    use 0x1::CDPOffer;
    use 0x1::Account;

    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun borrow_some_xfi(signer: &signer) {
        let borrowed = CDPOffer::borrow_amount<XFI, ETH>(signer, 50);
        Account::deposit_to_sender<XFI>(signer, borrowed);
    }
}
