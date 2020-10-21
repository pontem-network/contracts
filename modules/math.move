address 0x1 {
module Math {
    use 0x1::U256::{Self, U256};

    // max signs in u128
    const MAX_DECIMALS: u8 = 18;
    // 10^18
    const MAX_SCALING_FACTOR: u128 = 1000000000000000000;

    const MORE_THAN_18_DECIMALS_ERROR: u64 = 401;

    struct T { value: U256 }

    public fun create_from_u128(value: u128): T {
        T {
            value: U256::mul(U256::from_u128(value), U256::from_u128(MAX_SCALING_FACTOR)),
        }
    }

    public fun create_from_decimal(val: u64, decimals: u8): T {
        assert(decimals <= MAX_DECIMALS, MORE_THAN_18_DECIMALS_ERROR);

        let scaling_factor = pow_10(MAX_DECIMALS - decimals);
        // val is u64
        // scaling factor could be 10^18
        // multiple = <= u64 * <= u64 = <= u128
        let scaled = (val as u128) * scaling_factor;

        T { value: U256::from_u128(scaled) }
    }

    public fun pow(base: u64, exp: u8): u128 {
        let result_val = 1u128;
        let i = 0;
        while (i < exp) {
            result_val = result_val * (base as u128);
            i = i + 1;
        };
        result_val
    }

    fun pow_10(exp: u8): u128 {
        pow(10, exp)
    }

    public fun add(val1: T, val2: T): T {
        // if val1 <= u128 and val2 <= u128, combination could be > u128, so storing in U256
        let inner_val1 = as_u256(val1);
        let inner_val2 = as_u256(val2);
        T {
            value: U256::add(inner_val1, inner_val2)
        }
    }

    public fun sub(val1: T, val2: T): T {
        // if val1 <= u128 and val2 <= u128, combination could be > u128, so storing in U256
        let inner_val1 = as_u256(val1);
        let inner_val2 = as_u256(val2);
        T {
            value: U256::sub(inner_val1, inner_val2)
        }
    }

    public fun mul(val1: T, val2: T): T {
        let inner_val1 = as_u256(val1);
        let inner_val2 = as_u256(val2);

        // 36th dimension
        let unscaled = U256::mul(inner_val1, inner_val2);
        let scaling_factor = U256::from_u128(MAX_SCALING_FACTOR);

        // divide once by scaling factor to get back to 18th dimension
        let scaled = U256::div(unscaled, scaling_factor);

        T {
            value: scaled
        }
    }

    public fun div(val1: T, val2: T): T {
        let inner_val1 = as_u256(val1);
        // to account for underlying 18th dimension of val2
        let inner_val1_scaled = U256::mul(inner_val1, U256::from_u128(MAX_SCALING_FACTOR));

        let inner_val2 = as_u256(val2);

        // 36th dimension
        let value = U256::div(inner_val1_scaled, inner_val2);
        T { value }
    }

    public fun as_u256(num: T): U256 {
        let T { value } = num;
        value
    }

    public fun as_u128(num: T): u128 {
        // should fail with arithmetic error, if internal > u128
        let internal = as_u256(num);
        let scaled = U256::div(internal, U256::from_u128(MAX_SCALING_FACTOR));
        U256::as_u128(scaled)
    }

    public fun as_scaled_u128(num: T, decimals: u8): u128 {
        assert(decimals <= MAX_DECIMALS, MORE_THAN_18_DECIMALS_ERROR);

        let internal = as_u256(num);
        let scaling_factor = pow_10(MAX_DECIMALS - decimals);
        let scaled = U256::div(internal, U256::from_u128(scaling_factor));

        // if passed decimals is too small, and internal value > u128 => could be u128 overflow
        U256::as_u128(scaled)
    }

    public fun equals(a: &T, b: &T): bool {
        &a.value == &b.value
    }
}
}
