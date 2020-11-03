address 0x2 {
module Attic {

    use 0x1::Signer;

    resource struct T<S> {
        for: vector<S>
    }

    public fun take<S>(account: &signer): vector<S> acquires T {
        let owner = Signer::address_of(account);
        let T { for } = move_from<T<S>>(owner);

        for
    }

    public fun put<S>(account: &signer, for: vector<S>) {
        move_to<T<S>>(account, T { for });
    }

}
}
