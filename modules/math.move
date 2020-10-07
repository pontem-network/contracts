// eth: 0.00001 -> val(1, 5)
// btc: 0.0000001 -> val(1, 7)

// eth: 1.00000000000000000045 -> val(100000000000000000000045, 24)
// eth_btc: 0.002 -> val(2, 3)
// 1 eth / 0.002 btc
// (1_000_000_000, 9) * (2, 3) = (2_000_000)

module Math {
    use 0x1::U256;
    use 0x1::U256::U256;

    // max signs in u128
    const MAX_DECIMALS: u8 = 38;

    const ERROR_INTEGER_OVERFLOW: u64 = 501;

    struct Decimal {
        value: U256,
    }

    fun pow_10(exp: u8): U256 {
        let val = U256::from_u8(1);
        let i = 0;
        while (i < exp) {
            val = U256::mul(val, U256::from_u8(10));
            i = i + 1;
        };
        val
    }

    public fun val(base: u128, decimals: u8): Decimal {
        assert(decimals < MAX_DECIMALS, ERROR_INTEGER_OVERFLOW);
        Decimal {
            value: U256::mul(U256::from_u128(base), pow_10(MAX_DECIMALS - decimals))
        }
    }

    public fun sum(val1: Decimal, val2: Decimal): Decimal {
        let Decimal { value: val1_value } = val1;
        let Decimal { value: val2_value } = val2;
        Decimal { value: U256::add(val1_value, val2_value) }
    }

    public fun mul(val1: Decimal, val2: Decimal): Decimal {
        let Decimal { value: val1_value } = val1;
        let Decimal { value: val2_value } = val2;
        Decimal { value: U256::mul(val1_value, val2_value) }
    }

    public fun with_decimals(val: Decimal, decimals: u8): u128 {
        let Decimal { value: val_value } = val;
        if (decimals == MAX_DECIMALS) {
            U256::as_u128(val_value)
        } else {
            let divided = U256::div(val_value, U256::from_u8(MAX_DECIMALS - decimals));
            U256::as_u128(divided)
        }
    }

    public fun equals(val1: Decimal, val2: Decimal): bool {
        let Decimal { value: val1_value } = val1;
        let Decimal { value: val2_value } = val2;
        U256::as_u128(val1_value) == U256::as_u128(val2_value)
    }

}

