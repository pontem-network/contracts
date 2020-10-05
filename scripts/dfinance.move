address 0x0000000000000000000000000000000000000002 {
module Record {
    use 0x0000000000000000000000000000000000000001::Signer;
    resource struct T {
        age: u8
    }
    public fun loop_increment_1(arg: &signer, arg1: u8) acquires T  {
        let var: T;
        var = move_from<T>(Signer::address_of(arg));
        while (arg1 > 0u8) {
            arg1 = arg1 - 1u8;
            *&mut var.age = *&var.age + 1u8;
        };
        move_to<T>(arg, var);
    }
}
}
