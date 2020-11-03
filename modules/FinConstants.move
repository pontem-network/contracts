address 0x1 {

module FinConstants {

    use 0x1::Signer;

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
    resource struct CdpParams {
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64
    }

    /// Returns LTV, Soft MC and Hard MC
    public fun CDP(): (u64, u64, u64) acquires CdpParams {
        let p = borrow_global<CdpParams>(0x1);

        (
            p.max_ltv,
            p.soft_mc,
            p.hard_mc
        )
    }

    /// Set values for system-wide CDP Params
    public fun init_cdp_params(
        account: &signer,
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64
    ) {
        assert(is_system(account), 0);

        move_to<CdpParams>(account, CdpParams {
            max_ltv,
            soft_mc,
            hard_mc
        })
    }

    /// Change system-wide CDP params
    public fun change_cdp_params(
        account: &signer,
        max_ltv: u64,
        soft_mc: u64,
        hard_mc: u64
    ) acquires CdpParams {
        assert(is_system(account), 0);

        let p = borrow_global_mut<CdpParams>(0x1);

        p.max_ltv = max_ltv;
        p.soft_mc = soft_mc;
        p.hard_mc = hard_mc;
    }

    /// Check whether signer is 0x1 address
    fun is_system(account: &signer): bool {
        (Signer::address_of(account) == 0x1)
    }
}
}
