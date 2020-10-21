script {
    use 0x1::Math::{Self, create_from_u128, create_from_decimal, as_u128};

    fun main() {
        // 1
        let a = create_from_u128(6);
        let b = create_from_u128(2);
        let c = Math::div(a, b);
        assert(as_u128(c) == 3u128, 1);

        // 2
        let a1 = create_from_decimal(4, 18);
        let b1 = create_from_u128(2);
        let c1 = Math::div(a1, b1);
        assert(Math::equals(&c1, &create_from_decimal(2, 18)), 2);

        // 3
        let a2 = create_from_u128(3);
        let b2 = create_from_u128(2);
        let c2 = Math::div(a2, b2);
        assert(Math::equals(&c2, &create_from_decimal(15, 1)), 3);

        // 4
        let a2 = create_from_decimal(15, 1);  // 1.5
        let b2 = create_from_decimal(2, 1);  // 0.2
        let c2 = Math::div(a2, b2);  // should be 7.5
        assert(Math::equals(&c2, &create_from_decimal(75, 1)), 4);
    }
}