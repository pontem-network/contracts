script {

    use wallet12tg20s9g4les55vfvnumlkg0a5zk825py9j0ha::CDP;
    use 0x1::Coins::{BTC, USDT};
    use 0x1::Account;

    fun main(account: &signer, collateral_mul: u8, margin_call_at: u8) {
        CDP::create_offer<BTC, USDT>(
            account,
            Account::withdraw_from_sender<BTC>(account, 10000000),
            collateral_mul,
            margin_call_at
        );
    }
}
