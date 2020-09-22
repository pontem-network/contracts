script {

    use 0x1::Debug;
    use 0x1::Account;

    fun main(account: &signer) {

        let _ = account;
        let a = 120;

        Debug::print<u8>(&a);

        // let _ = CDP::has_offer<u64, u128>(0x2);
        let _ = Account::balance<u64>(account);
    }
}
