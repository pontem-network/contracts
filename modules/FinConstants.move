address 0x1 {

module FinConstants {

    /// Loan-to-Value. Percent at which Margin Call is made.
    /// Defined by governance. Real loan amount must be lesser
    /// than constant LTV value.
    const LOAN_TO_VALUE : u8 = 66;

    public fun LTV(): u8 {
        LOAN_TO_VALUE
    }
}

// module M {
//   // or maybe even add :resource constraint!
//   struct T1<R:resource> {}
//   resource struct K {}

//   public fun test() {
//     // obviously value is not a resource, only by its type
//     let _ = T1<K>{};
//   }
// }

/// Properties of the deal:
/// - always stored at borrower's address
/// -
module CDP_DRO {

    use 0x1::Dfinance;
    use 0x1::Coupon;
    use 0x1::Signer;

    struct Option<Curr: copyable, Exch: copyable> {
        borrower: address,
        // what is going to happen if coupon expired?
        // well, there should be some logic to cover it...
        // but this logic cannot be placed inside this module
        // why? because coupon match-destroy can only be handled
        // by the origin module which is a coupon module
        // ...and who would want to spend additional time and MONEY
        // on destroying coupon that has expired? Nobody. Word!
        // let's look from another side. Is there a problem in storing
        // coupon at all? I mean in this case they would exist on balance
        // forever, right, but who cares? Even if someone has 1000 coupons...
        // will if affect performance?
        // resource viewer is a MUST, bruh. For these cases definetely

        // expiration: u64 // maybe put expiration date here?
    }

    resource struct Bank<Curr, Exch> {
        stored: Dfinance::T<Curr>
    }

    resource struct CDP<Curr: copyable, Exch: copyable> {
        lender: address,
        permission: Coupon::DestroyPermission<Option<Curr, Exch>>
    }

    resource struct Offer<Curr: copyable, Exch: copyable> {
        lender: address
    }

    public fun make_offer<Curr: copyable, Exch: copyable>(account: &signer) {
        let lender = Signer::address_of(account);

        move_to<Offer<Curr, Exch>>(account, Offer {
            lender
        });
    }

    public fun accept_offer<Curr: copyable, Exch: copyable>(
        account: &signer,
        lender: address
    ) acquires Offer {

        let borrower = Signer::address_of(account);
        let Offer { lender } = move_from<Offer<Curr, Exch>>(lender);
        let permission = Coupon::issue<Option<Curr, Exch>>(account, Option {
            borrower
        });

        move_to<CDP<Curr, Exch>>(account, CDP {
            permission,
            lender
        });
    }

    public fun close_dro_deal<Curr: copyable, Exch: copyable>(
        account: &signer
    ) acquires CDP {
        let me = Signer::address_of(account);
        let CDP { lender: _, permission } = move_from<CDP<Curr, Exch>>(me);
        let coupon = Coupon::take<Option<Curr, Exch>>(account);

        Coupon::destroy<Option<Curr, Exch>>(coupon, permission);
    }
}

module CouponStorage {

    use 0x1::Coupon::T as Coupon;
    use 0x1::Vector;
    use 0x1::Signer;

    resource struct T<For> {
        coupons: vector<Coupon<For>>
    }

    public fun init<For>(account: &signer) {
        move_to<T<For>>(account, T {
            coupons: Vector::empty<Coupon<For>>()
        });
    }

    public fun push<For>(
        account: &signer,
        coupon: Coupon<For>
    ) acquires T {
        Vector::push_back(
            &mut borrow_global_mut<T<For>>(Signer::address_of(account)).coupons
            , coupon
        );
    }

    public fun take<For>(
        account: &signer,
        el: u64
    ): Coupon<For> acquires T {
        let me  = Signer::address_of(account);
        let vec = &mut borrow_global_mut<T<For>>(me).coupons;

        Vector::remove(vec, el)
    }

}

/// Coupon is a new pattern-candidate for standard library.
/// In basic terms it's locker-key pair, where locker may contain any type
/// of asset in it, while key is a hot potato which cannot be stored directly
/// at any address and must be placed somewhere else.
///
/// Owner of the locker (or Coupon) knows what's inside, he can read the stored
/// data and estimate its value (or know something about the deal/reasons for
/// creation) while not being able to unlock this locker without the proper
/// key for it. Key may be placed into a Financial contract module which will
/// control the conditions under which this locker can be unlocked (in terms
/// of Move - destroyed). While coupon itself may travel through chain carrying
/// the data hidden in it.
///
/// In terms of security this pair is safe, as coupon-locker and its destroy
/// permission-key are matched by signer's address and ID. For every coupon
/// there's only one key (permission) which can unlock it.
///
/// It is also possible to let governance (0x1 or different address) unlock
/// these coupons if key got lost or deal is no longer profitable. Though it is
/// up to creator of the coupon to decide what should be put inside.
///
/// Multiple coupons might be united by the same dataset stored inside of them.
/// This can allow developers implement their multi-coupon sets. And only
/// imagination is the limit to these features.
///
/// I also mean the coupon as some analogy to financial security. Creator of the
/// coupon is the Issuer of the security, he knows what this security means and
/// he defines the way of how it can be used. And while in this case the coupon
/// would carry only some information about an underlying asset we prevent this
/// asset from moving across the network - hence we bypass the obligation to track
/// every asset in chain.
module Coupon {

    public fun destroy_p<For>(p: DestroyPermission<For>) {
        let DestroyPermission { id: _, by: _ } = p;
    }

    use 0x1::Signer;

    resource struct Info {
        coupon_count: u64
    }

    resource struct T<For> {
        for: For,
        by: address,
        id: u64
    }

    resource struct DestroyPermission<For> {
        by: address,
        id: u64
    }

    public fun issue<For>(
        account: &signer,
        for: For
    ): DestroyPermission<For> acquires Info {

        let by = Signer::address_of(account);
        let id = if (!has_info(by)) {
            move_to(account, Info {
                coupon_count: 1
            });
            1
        } else {
            let info = borrow_global_mut<Info>(by);
            info.coupon_count = info.coupon_count + 1;
            info.coupon_count
        };

        move_to<T<For>>(account, T { for, by, id });

        DestroyPermission<For> { by, id }
    }

    public fun has_info(account: address): bool {
        exists<Info>(account)
    }

    public fun has_coupon<For>(account: address): bool {
        exists<T<For>>(account)
    }

    public fun borrow<For>(coupon: &T<For>): &For {
        &coupon.for
    }

    public fun put<For>(account: &signer, coupon: T<For>) {
        move_to<T<For>>(account, coupon);
    }

    public fun take<For>(account: &signer): T<For> acquires T {
        move_from<T<For>>(Signer::address_of(account))
    }

    public fun destroy<For>(
        coupon: T<For>,
        permission: DestroyPermission<For>
    ): For {

        assert(coupon.by == permission.by, 1000);
        assert(coupon.id == permission.id, 1000);

        let T { by: _, id: _, for } = coupon;
        let DestroyPermission { by: _, id: _ } = permission;

        for
    }
}
}
