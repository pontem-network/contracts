script {
    use 0x1::Math::{Self, create_from_u128, create_from_decimal, as_u128};

    fun main() {
        // 1
        let a = create_from_u128(2);
        let b = create_from_u128(3);
        let c = Math::mul(a, b);
        assert(as_u128(c) == 6u128, 1);

        // 2
        let a1 = create_from_decimal(2, 18);
        let b1 = create_from_decimal(3, 18);
        let c1 = Math::mul(a1, b1);
        assert(Math::equals(&c1, &create_from_u128(0)), 2);

        // 3
        let a2 = create_from_decimal(1, 18);
        let b2 = create_from_u128(2);  // 2
        let c2 = Math::mul(a2, b2);
        assert(Math::equals(&c2, &create_from_decimal(2, 18)), 3);

        // 4
        let a2 = create_from_decimal(1, 15);  // 1 * 10^-15
        let b2 = create_from_decimal(2, 3);  // 2 * 10^-3
        let c2 = Math::mul(a2, b2);
        assert(Math::equals(&c2, &create_from_decimal(2, 18)), 4);
    }
}