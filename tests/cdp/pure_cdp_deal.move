// Test default CDP scenario:
// Interest Rate: 0.00 %
// LTV: 30%
// ETH-XFI price: 100.00
// ETH Collateral: 1 ETH
// XFI Received: 30 [+]
// Soft MC ETH-XFI: 45 [+]
// Hard MC ETH-XFI: 39 [+]
// Max LTV: 66.00%
//
// For more information see:
// https://docs.google.com/spreadsheets/d/1E5r40dOtfd_fGvpMXh98PykJYXezJ8HuLzQZTuICK1Q/edit#gid=1094305678

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

/// signers: 0xDF1
/// current_time: 1609448400
/// price: eth_xfi 10000000000
script {
    use 0x1::CDP;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;

    // 100 XFI balance of the bank
    fun create_offer_with_params(account: &signer) {
        let deposit  = Dfinance::mint<XFI>(100000000000000000000);
        let min_ltv  = 1000; // 10.00%
        let int_rate = 1000; // 10.00%
        let buy_gate = 0;    // 1 day for DRO

        CDP::create_offer<XFI, ETH>(
            account,
            deposit,
            min_ltv,
            int_rate,
            100000000, // duration
            false, // allow dro
            buy_gate
        );
    }
}

// Date start: 01.01.2021 - 1609448400
/// signers: 0x2
/// current_time: 1609448400
/// price: eth_xfi 10000000000
script {
    use 0x1::Account;
    use 0x1::Security;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;
    use 0x1::CDP::{Self, CDP};
    use 0x1::SecurityStorage;

    fun make_cdp_deal(account: &signer) {

        SecurityStorage::init<CDP<XFI, ETH>>(account);

        // 1 ETH Collateral value
        let collateral = Dfinance::mint<ETH>(1000000000000000000);

        let (xfi, security) = CDP::make_deal<XFI, ETH>(
            account,
            0xDF1,
            collateral,
            30000000000000000000 // 30 XFI wanted
        );

        let cdp_sec = Security::borrow<CDP<XFI, ETH>>(&security);
        let (lender, deal_id) = CDP::read_security(cdp_sec);
        let (
            ltv,
            soft_mc,
            hard_mc,
            created_at,
            interest_rate,
            offered_amt,
            collateral_amt
        ) = CDP::get_deal_details<XFI, ETH>(lender, deal_id);

        SecurityStorage::push<CDP<XFI, ETH>>(account, security);
        Account::deposit_to_sender<XFI>(account, xfi);

        assert(ltv == 3000, 1);
        assert(soft_mc == 4500000000, 2);
        assert(hard_mc == 3900000000, 3);

        assert(offered_amt == 30000000000000000000, 4);
        assert(collateral_amt == 1000000000000000000, 5);
        assert(interest_rate == 1000, 6);
        assert(created_at == 1609448400, 7);

        let status = CDP::get_deal_status_by_id<XFI, ETH>(lender, deal_id);

        assert(status == 1, 8);
    }
}

// Rate reached Soft Margin Call - check Deal Status
/// price: eth_xfi 4500000000
/// current_time: 1609448400
/// signers: 0x2
script {

    use 0x1::Security;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;
    use 0x1::SecurityStorage;
    use 0x1::CDP::{Self, CDP};

    fun check_deal_status_on_soft_mc(account: &signer) {

        let security = SecurityStorage::take<CDP<XFI, ETH>>(account, 0);
        let sec_cdp  = Security::borrow(&security);
        let (lender, deal_id) = CDP::read_security<XFI, ETH>(sec_cdp);

        let status = CDP::get_deal_status_by_id<XFI, ETH>(lender, deal_id);

        assert(status == 2, 1); // STATUS_SOFT_MC_REACHED

        SecurityStorage::push<CDP<XFI, ETH>>(account, security);
    }
}

// Rate reached Hard Margin Call - borrower tries
// to return his debt and fails.

/// price: eth_xfi 3900000000
/// current_time: 1609448400
/// signers: 0x2
/// aborts_with: 301
script {

    use 0x1::Account;
    use 0x1::Security;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;
    use 0x1::SecurityStorage;
    use 0x1::CDP::{Self, CDP};

    fun check_deal_status_on_hard_mc(account: &signer) {

        let security = SecurityStorage::take<CDP<XFI, ETH>>(account, 0);
        let sec_cdp  = Security::borrow(&security);
        let (lender, deal_id) = CDP::read_security<XFI, ETH>(sec_cdp);

        let status = CDP::get_deal_status_by_id<XFI, ETH>(lender, deal_id);

        assert(status == 3, 1); // STATUS_HARD_MC_REACHED

        // TRY TO PAY BACK BUT RECEIVE 'ERR_HARD_MC_HAS_OCCURRED'

        let collateral = CDP::pay_back(account, security);
        Account::deposit_to_sender<ETH>(account, collateral);
    }
}

// Lender does nothing, rate gets back to above the Hard MC level
// borrower can pay his debt.

/// price: eth_xfi 4500000000
/// current_time: 1609448400
/// signers: 0x2
/// aborts_with: 301
script {

    use 0x1::Account;
    use 0x1::Security;
    use 0x1::Dfinance;
    use 0x1::Coins::ETH;
    use 0x1::XFI::T as XFI;
    use 0x1::SecurityStorage;
    use 0x1::CDP::{Self, CDP};

    fun check_deal_status_on_hard_mc(account: &signer) {

        let security = SecurityStorage::take<CDP<XFI, ETH>>(account, 0);
        let sec_cdp  = Security::borrow(&security);
        let (lender, deal_id) = CDP::read_security<XFI, ETH>(sec_cdp);

        let status = CDP::get_deal_status_by_id<XFI, ETH>(lender, deal_id);

        assert(status == 2, 1); // STATUS_SOFT_MC_REACHED

        // 30.000000000000000000 // 30 XFI + 0.008... INTEREST RATE
        // 30.008219178082191780 // Expected total pay back sum

        // just enough to pay interest rate
        let xfi_ret  = Dfinance::mint<XFI>(8219178082191780);
        Account::deposit_to_sender<XFI>(account, xfi_ret);

        let collateral = CDP::pay_back(account, security);
        Account::deposit_to_sender<ETH>(account, collateral);
    }
}

