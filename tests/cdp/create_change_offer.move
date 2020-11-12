/// signers: 0x1
script {
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::FinConstants;
    use 0x1::XFI::T as XFI;

    fun prelude(account: &signer) {
        Dfinance::register_coin<ETH>(account, b"eth", 18);
        Dfinance::register_coin<XFI>(account, b"xfi", 18);

        FinConstants::init_cdp_params(account,
             6600, // max ltv
            15000, // soft mc
            13000, // hard mc
            2,     // 2 days max duration of deal
        );
    }
}

/// current_time: 0
/// signers: 0xDF1
/// price: eth_xfi 10000000000
/// aborts_with: 104
script {
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun cannot_deposit_if_offer_does_not_exist(account: &signer) {
        // 100 XFI
        let dep_amt = 100000000000000000000;
        let deposit = Dfinance::mint<XFI>(dep_amt);

        CDP::deposit<XFI, ETH>(account, 0x103, deposit);
    }
}

/// current_time: 0
/// signers: 0xDF1
/// price: eth_xfi 10000000000
/// aborts_with: 104
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun cannot_withdraw_if_offer_does_not_exist(account: &signer) {
        // 100 XFI
        let dep_amt = 100000000000000000000;
        let withdrawn = CDP::withdraw<XFI, ETH>(account, dep_amt);
        Account::deposit_to_sender(account, withdrawn);
    }
}

/// signers: 0xDF1
/// current_time: 0
/// price: eth_xfi 10000000000
/// price: xfi_eth 1
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun create_offer_with_params(account: &signer) {
        let deposit  = Dfinance::zero<XFI>();
        let min_ltv  = 1000; // 10%
        let int_rate = 1000; // 10%
        let buy_gate = 0;    // 1 day for DRO
        let lender   = Signer::address_of(account);

        CDP::create_offer<XFI, ETH>(
            account,
            deposit,
            min_ltv,
            int_rate,
            false, // allow dro
            buy_gate
        );

        assert(CDP::has_offer<XFI, ETH>(lender), 1);

        let (dep, ltv, ir, active, dro, gate) = CDP::get_offer_details<XFI, ETH>(lender);

        assert(
            dep == 0       &&
            ltv == min_ltv &&
            ir == int_rate &&
            active == true &&
            dro == false   &&
            gate == 0,
        2);

        CDP::deactivate_offer<XFI, ETH>(account);
        let (_, _, _, active, _, _) = CDP::get_offer_details<XFI, ETH>(lender);
        assert(active == false, 3);

        CDP::activate_offer<XFI, ETH>(account);
        let (_, _, _, active, _, _) = CDP::get_offer_details<XFI, ETH>(lender);
        assert(active == true, 4);
    }
}

/// signers: 0xDF1
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun deposit_and_withdraw(account: &signer) {
        let dep_amt = 100000000000000000000;
        let deposit = Dfinance::mint<XFI>(dep_amt);
        let lender  = Signer::address_of(account);

        CDP::deposit<XFI, ETH>(account, lender, deposit);

        let (amount, _, _, _, _, _) = CDP::get_offer_details<XFI, ETH>(lender);

        assert(amount == dep_amt, 1);

        let withdrawn = CDP::withdraw<XFI, ETH>(account, dep_amt / 2);
        let (amount, _, _, _, _, _) = CDP::get_offer_details<XFI, ETH>(lender);

        assert(amount == 50000000000000000000, 2);

        Account::deposit_to_sender(account, withdrawn);
    }
}

/// signers: 0xDF1
script {
    use 0x1::CDP;
    use 0x1::Signer;
    use 0x1::Account;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun withdraw_all(account: &signer) {
        let lender    = Signer::address_of(account);
        let withdrawn = CDP::withdraw_all<XFI, ETH>(account);

        let (amount, _, _, _, _, _) = CDP::get_offer_details<XFI, ETH>(lender);

        assert(amount == 0, 1);

        Account::deposit_to_sender(account, withdrawn);
    }
}

/// signers: 0xDF1
/// aborts_with: 200
script {
    use 0x1::CDP;
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    fun try_withdraw_from_empty(account: &signer) {
        let withdrawn = CDP::withdraw_all<XFI, ETH>(account);

        Dfinance::destroy_zero<XFI>(withdrawn);

        let try_withdraw = CDP::withdraw<XFI, ETH>(account, 10);

        Account::deposit_to_sender(account, try_withdraw);
    }
}

