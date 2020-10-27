script {
    use 0x1::Security;
    use 0x1::SecurityStorage;

    // gas for 1000 securities: main(gas: 72301)
    // gas for 100  securities: main(gas: 7246)
    // gas for 10   securities: main(gas: 740)

    fun main(account: &signer) {
        let i = 1;

        SecurityStorage::init<u64>(account);

        while (i < 100) {
            let (sec, proof) = Security::issue<u64>(account, i);
            SecurityStorage::push<u64>(account, sec);
            Security::destroy_proof(proof);
            i = i + 1;
        }
    }
}
