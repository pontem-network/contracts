address 0x1 {

module TestVecResource {

    use 0x1::Signer;
    use 0x1::Vector;

    resource struct T<S> {
        for: vector<S>
    }

    public fun empty<S>(): vector<S> {
        Vector::empty<S>()
    }

    public fun take<S>(account: &signer): vector<S> acquires T {
        let owner = Signer::address_of(account);
        let T { for } = move_from<T<S>>(owner);

        for
    }

    public fun put<S>(account: &signer, for: vector<S>) {
        move_to<T<S>>(account, T { for });
    }

}}
