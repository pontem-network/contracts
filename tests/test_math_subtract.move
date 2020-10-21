script {
    use 0x1::Math::{Self, create_from_u128, create_from_decimal, as_u128};

    fun main() {
        // 1
        let a = create_from_u128(3);
        let b = create_from_u128(1);
        let c = Math::sub(a, b);
        assert(as_u128(c) == 2u128, 1);

        // 2
        let a1 = create_from_decimal(3, 18);
        let b1 = create_from_decimal(1, 18);
        let c1 = Math::sub(a1, b1);
        assert(Math::equals(&c1, &create_from_decimal(2, 18)), 2);

        // 3
        let a2 = create_from_decimal(1, 17);  // 10
        let b2 = create_from_decimal(2, 18);  // 2
        let c2 = Math::sub(a2, b2);
        assert(Math::equals(&c2, &create_from_decimal(8, 18)), 3);
    }
}