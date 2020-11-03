/// signers: 0x2
/// current_time: 0
script {
    use 0x1::Security::{Self, Proof};
    use 0x1::SecurityStorage;
    use 0x1::Vector;
    use 0x2::Attic;

    fun issue_security_with_expiration(account: &signer) {

        SecurityStorage::init<u128>(account);

        let (sec, proof) = Security::issue<u128>(account, 1000, 100);
        let proof_vec    = Vector::empty<Proof>();

        Vector::push_back<Proof>(&mut proof_vec, proof);

        // store security and proof
        SecurityStorage::push(account, sec);
        Attic::put(account, proof_vec);
    }
}

/// signers: 0x2
/// current_time: 99
/// aborts_with: 102
script {
    use 0x1::SecurityStorage;
    use 0x1::Security;

    fun take_security_and_check_expiration(account: &signer) {

        let sec = SecurityStorage::take<u128>(account, 0);
        Security::destroy_expired_sec(sec);
    }
}

/// signers: 0x2
/// current_time: 99
/// aborts_with: 102
script {
    use 0x1::Security::{Self, Proof};
    use 0x1::Vector;
    use 0x2::Attic;

    fun take_proof_and_check_expiration(account: &signer) {

        let vec = Attic::take<Proof>(account);
        let prf = Vector::remove(&mut vec, 0);

        Security::destroy_expired_proof(prf);

        Attic::put<Proof>(account, vec);
    }
}

/// signers: 0x2
/// current_time: 100
script {
    use 0x1::SecurityStorage;
    use 0x1::Security;

    fun take_security_and_destroy_expired(account: &signer) {

        let sec = SecurityStorage::take<u128>(account, 0);
        let num = Security::destroy_expired_sec(sec);

        assert(num == 1000, 42);
    }
}

/// signers: 0x2
/// current_time: 100
script {
    use 0x1::Security::{Self, Proof};
    use 0x1::Vector;
    use 0x2::Attic;

    fun take_proof_and_destroy_expired(account: &signer) {

        let vec = Attic::take<Proof>(account);
        let prf = Vector::remove(&mut vec, 0);

        Security::destroy_expired_proof(prf);

        Attic::put<Proof>(account, vec);
    }
}
