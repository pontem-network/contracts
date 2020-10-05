script {

    use wallet12tg20s9g4les55vfvnumlkg0a5zk825py9j0ha::CDP;
    use 0x1::Coins::{BTC, USDT};

    fun main(account: &signer, lender: address) {
        CDP::take_offer<BTC, USDT>(account, lender);
    }
}
