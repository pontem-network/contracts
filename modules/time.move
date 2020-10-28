address 0x1 {
module Time {

    const SECONDS_IN_DAY : u64 = 86400;
    const SECONDS_IN_MIN : u64 = 60;

    /// A singleton resource holding the current Unix time in seconds
    resource struct CurrentTimestamp {
        seconds: u64,
    }

    public fun init_time(account: &signer, seconds: u64) {
        assert(0x1::Signer::address_of(account) == 0x1, 9999);
        move_to(account, CurrentTimestamp { seconds });
    }

    public fun set_time(seconds: u64) acquires CurrentTimestamp {
        let time = borrow_global_mut<CurrentTimestamp>(0x1);
        time.seconds = seconds;
    }

    /// Get the timestamp representing `now` in seconds.
    public fun now(): u64 acquires CurrentTimestamp {
        borrow_global<CurrentTimestamp>(0x1).seconds
    }

    public fun days_from(ts: u64): u64 acquires CurrentTimestamp {
        let rn = now();
        assert(rn > ts, 0);
        (rn - ts) / SECONDS_IN_DAY
    }

    public fun minutes_from(ts: u64): u64 acquires CurrentTimestamp {
        let rn = now();
        assert(rn > ts, 0);
        (rn - ts) / SECONDS_IN_MIN
    }

    /// Helper function to determine if the blockchain is at genesis state.
    public fun is_genesis(): bool {
        !exists<CurrentTimestamp>(0x1)
    }
}
}
