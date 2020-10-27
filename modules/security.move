address 0x1 {

/// Security is a new pattern-candidate for standard library.
/// In basic terms it's locker-key pair, where locker may contain any type
/// of asset in it, while key is a hot potato which cannot be stored directly
/// at any address and must be placed somewhere else.
///
/// Owner of the locker (or Security) knows what's inside, he can read the stored
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
module Security {

    public fun destroy_proof(proof: Proof) {
        let Proof { by: _, id: _ } = proof;
    }

    use 0x1::Signer;

    const ERR_UNABLE_TO_PROVE : u64 = 1001;

    resource struct Info {
        securities_count: u64
    }

    resource struct Security<For> {
        for: For,
        by: address,
        id: u64
    }

    resource struct Proof {
        by: address,
        id: u64
    }

    public fun issue<For>(
        account: &signer,
        for: For
    ): (Security<For>, Proof) acquires Info {

        let by = Signer::address_of(account);
        let id = if (!has_info(by)) {
            move_to(account, Info { securities_count: 1 });
            1
        } else {
            let info = borrow_global_mut<Info>(by);
            info.securities_count = info.securities_count + 1;
            info.securities_count
        };

        (
            Security { for, by, id },
            Proof { by, id }
        )
    }

    /// Check whether user already has securities issued from his account
    public fun has_info(account: address): bool {
        exists<Info>(account)
    }

    public fun has_security<For>(account: address): bool {
        exists<Security<For>>(account)
    }

    public fun borrow<For>(security: &Security<For>): &For {
        &security.for
    }

    public fun put<For>(account: &signer, security: Security<For>) {
        move_to<Security<For>>(account, security);
    }

    public fun take<For>(account: &signer): Security<For> acquires Security {
        move_from<Security<For>>(Signer::address_of(account))
    }
    
    public fun can_prove<For>(security: &Security<For>, proof: &Proof): bool {
        (security.id == proof.id && security.by == proof.by)
    }

    /// Prove that Security matches given Proof. This method makes sure that
    /// issuer account address and security ID match. When success - releases
    /// data (or resource) stored inside Security.
    public fun prove<For>(
        security: Security<For>,
        proof: Proof
    ): For {

        assert(security.by == proof.by, ERR_UNABLE_TO_PROVE);
        assert(security.id == proof.id, ERR_UNABLE_TO_PROVE);

        let Security { by: _, id: _, for } = security;
        let Proof { by: _, id: _ } = proof;

        for
    }
}

module SecurityStorage {

    use 0x1::Security::{Security};
    use 0x1::Vector;
    use 0x1::Signer;

    resource struct T<For> {
        securities: vector<Security<For>>
    }

    public fun init<For>(account: &signer) {
        move_to<T<For>>(account, T {
            securities: Vector::empty<Security<For>>()
        });
    }

    public fun push<For>(
        account: &signer,
        security: Security<For>
    ) acquires T {
        Vector::push_back(
            &mut borrow_global_mut<T<For>>(Signer::address_of(account)).securities
            , security
        );
    }

    public fun take<For>(
        account: &signer,
        el: u64
    ): Security<For> acquires T {
        let me  = Signer::address_of(account);
        let vec = &mut borrow_global_mut<T<For>>(me).securities;

        Vector::remove(vec, el)
    }
}
}
