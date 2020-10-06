script {

    use 0x1::Debug;
    use 0x1::Account;
    use 0x1::Dfinance::{
        create_token,
        Token,
        Self,
    };

    fun main(account: &signer) {
        let my_tok = create_token<u64>( account, 100, 0, b"mytok" );
        Account::deposit_to_sender<Token<u64>>(account, my_tok);

        Debug::print<u128>(&Dfinance::total_supply<Token<u64>>());
        Debug::print<vector<u8>>(&Dfinance::denom<Token<u64>>());
        Debug::print<address>(&Dfinance::owner<Token<u64>>());
    }
}
