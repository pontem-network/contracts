script {
    use 0x1::Math;
//    use 0x1::Debug;

    fun main() {
        let btc1 = Math::create_from_decimal(1, 2); // 0.01
        let btc2 = Math::create_from_decimal(2, 3);  // 0.002
        let sum = Math::add(btc1, btc2);  // 0.012 or (12, 3)
        0x1::Debug::print(&Math::as_u256(copy sum));
        0x1::Debug::print(&Math::as_scaled_u128(copy sum, 3));

        let btc = Math::create_from_decimal(1, 2); // 0.01
        let btc_eth = Math::create_from_u128(10); // 10

        let eth = Math::mul(btc, btc_eth); // 0.1 or (1000000000000000(18 signs), 18)
        0x1::Debug::print(&Math::as_scaled_u128(copy eth, 1)); // 1
        0x1::Debug::print(&Math::as_scaled_u128(copy eth, 2)); // 10
    }
}