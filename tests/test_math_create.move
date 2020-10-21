/// test different ways to create number
script {
    use 0x1::Math::{create_from_u128, create_from_decimal, as_u128, as_scaled_u128};

    fun main() {
        // 1
        // from u128
        let num = create_from_u128(1);
        assert(as_u128(num) == 1u128, 1);

        // 2
        // from decimals
        let num2 = create_from_decimal(1, 17); // 10 * 10^-18
        assert(as_u128(num2) == 0, 2);

        // 3
        // different decimal forms
        let num3 = create_from_decimal(1, 9); // 1_000_000_000 * 10^-18
        assert(as_scaled_u128(num3, 12) == 1000, 3);

        // 4
        let num4 = create_from_decimal(1, 9); // 1_000_000_000 * 10^-18
        assert(as_scaled_u128(num4, 14) == 100000, 4);

        // 5
        let num5 = create_from_decimal(1, 9); // 1_000_000_000 * 10^-18
        assert(as_scaled_u128(num5, 16) == 10000000, 5);
    }
}