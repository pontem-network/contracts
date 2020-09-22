address 0x1 {

module Oracle {

    resource struct Price<Curr1, Curr2> {
        value: u64
    }

    public fun init_price<Curr1, Curr2>(account: &signer, value: u64) {
        move_to<Price<Curr1, Curr2>>(account, Price { value })
    }

    public fun set_price<Curr1, Curr2>(value: u64) acquires Price {
        let price = borrow_global_mut<Price<Curr1, Curr2>>(0x1);
        price.value = value;
    }

    public fun get_price<Curr1, Curr2>(): u64 acquires Price {
        borrow_global<Price<Curr1, Curr2>>(0x1).value
    }

    public fun has_price<Curr1, Curr2>(): bool {
        exists<Price<Curr1, Curr2>>(0x1)
    }
}

}
