address 0x1 {

module FinConstants {

    use 0x1::Signer;

    const ERR_INSUFFICIENT_PRIVILEGE: u64 = 101;

    /// Holds LTV, Soft Margin Call and Hard Margin Call
    ///
    /// * LTV - Loan-to-Value. Percent at which Margin Call is made.
    /// Defined by governance. Real loan amount must be lesser
    /// than constant LTV value.
    /// * Soft Margin Call - price change (%) at which DRO can be
    /// used to buy out collateral
    /// * Hard Margin Call - price change (%) at which Collateral can
    /// be liquidated by Lender, and borrower can no longer pay back
    /// his debt.
    /// * Duration - max number of days for CDP deal. When deadline
    /// is reached, collateral can be liquidated by lender
    resource struct CdpParams {
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64,
        duration: u64 // how many days
    }

    /// Returns LTV, Soft MC and Hard MC
    public fun CDP(): (u64, u64, u64, u64) acquires CdpParams {
        let p = borrow_global<CdpParams>(0x1);

        (
            p.max_ltv,
            p.soft_mc,
            p.hard_mc,
            p.duration
        )
    }

    /// Set values for system-wide CDP Params
    public fun init_cdp_params(
        account: &signer,
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64,
        duration: u64
    ) {
        assert_is_system(account);

        move_to<CdpParams>(account, CdpParams {
            max_ltv,
            soft_mc,
            hard_mc,
            duration,
        })
    }

    /// Change system-wide CDP params
    public fun change_cdp_params(
        account: &signer,
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64,
        duration: u64
    ) acquires CdpParams {
        assert_is_system(account);

        let p = borrow_global_mut<CdpParams>(0x1);

        p.max_ltv  = max_ltv;
        p.soft_mc  = soft_mc;
        p.hard_mc  = hard_mc;
        p.duration = duration
    }

    /// Check whether signer is 0x1 address
    fun assert_is_system(account: &signer) {
        assert(Signer::address_of(account) == 0x1, ERR_INSUFFICIENT_PRIVILEGE)
    }
}
}
