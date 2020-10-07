script {
    use 0x1::Math;

    fun main() {
        let val1 = Math::val(12000, 18);
        let val2 = Math::val(20, 15);

        let expected = 32000;
        let actual = Math::sum(val1, val2);

        assert(expected == Math::with_decimals(actual, 18), 401);
    }
}