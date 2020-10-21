script {
    use 0x1::Math::{Self, create_from_u128, create_from_decimal, as_u128};

    fun main() {
        // 1
        let a = create_from_u128(1);
        let b = create_from_u128(2);
        let c = Math::add(a, b);
        assert(as_u128(c) == 3u128, 1);

        // 2
        let a1 = create_from_decimal(1, 18);
        let b1 = create_from_decimal(2, 18);
        let c1 = Math::add(a1, b1);
        assert(Math::equals(&c1, &create_from_decimal(3, 18)), 2);

        // 3
        let a2 = create_from_decimal(1, 18);  // 1
        let b2 = create_from_decimal(2, 17);  // 20
        let c2 = Math::add(a2, b2);
        assert(Math::equals(&c2, &create_from_decimal(21, 18)), 3);
    }
}