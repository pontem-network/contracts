script {
    use 0x1::Signer;
    use 0x1::Coupon;
    use 0x1::Vector;
    use 0x1::Debug;
    use 0x1::CouponStorage as Store;

    fun main(acc: &signer) {

        let _ = Signer::address_of(acc);
        let i = 0;

        Store::init<u8>(acc);

        while (i < 10) {

            let p = Coupon::issue<u8>(acc, i * 10);
            let c = Coupon::take<u8>(acc);

            Store::push<u8>(acc, c);
            Coupon::destroy_p(p);

            i = i + 1;
        };

        let vec = Vector::empty<Coupon::T<u8>>();

        while (i > 0) {

            i = i - 1;

            let c = Store::take(acc, (i as u64));
            Debug::print<u8>(Coupon::borrow<u8>(&c));
            Vector::push_back(&mut vec, c);
        };

        while (i < 10) {
            let c = Vector::pop_back(&mut vec);
            Store::push<u8>(acc, c);

            i = i + 1;
        };

        Vector::destroy_empty(vec);

        // Coupon::destroy(acc, c, p);
    }
}
