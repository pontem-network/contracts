// Test case #1
//
// 1. Mint coins for Account (ETH, BTC)
// 2. Mock Oracle prices for ETH -> BTC
// 3.

address 0x3 {
module Steps {
    // standard library
//    use 0x1::Debug;
//    use 0x1::Signer;
    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};

    // custom dependencies
//    use 0x1::Auction;
//    use 0x1::Oracle;
//    use 0x1::CDP;

    fun put_coins_to_balance<Coin>(signer: &signer, n: u128) {
        let coin = Dfinance::mint<Coin>(n);
        Account::deposit_to_sender<Coin>(signer, coin);
    }

    public fun mint_coins_and_put_them_to_sender_balance(usr_one: &signer, usr_two: &signer): (u128, u128) {
        put_coins_to_balance<ETH>(usr_one, 1000);
        put_coins_to_balance<BTC>(usr_two, 1000);

        let eth_balance = Account::balance<ETH>(usr_one);
        let btc_balance = Account::balance<BTC>(usr_two);

        return (eth_balance, btc_balance)
    }

    fun give_etherium_to_bidder(bidder: &signer, n: u128) {
        Account::deposit_to_sender<ETH>(bidder, Dfinance::mint<ETH>(n))
    }

    public fun give_some_etherium_to_bidders(usr_bid1: &signer, usr_bid2: &signer, usr_bid3: &signer) {
        give_etherium_to_bidder(usr_bid1, 1000);
        give_etherium_to_bidder(usr_bid2, 1000);
        give_etherium_to_bidder(usr_bid3, 1000);
    }
}
}

/// signer: 0x1
/// signer: 0x2
/// signer: 0x3
/// signer: 0x11
/// signer: 0x12
/// signer: 0x13
script {
    // standard library
    use 0x1::Debug;
    //    use 0x1::Signer;
    //    use 0x1::Account;
    use 0x1::Dfinance;
    use 0x1::Coins::{ETH, BTC};
    // custom dependencies
//    use 0x1::Auction;
    use 0x1::Oracle;
    //    use 0x1::CDP;

    use 0x3::Steps;

    fun main(std_acc: &signer, usr_one: &signer, usr_two: &signer,
             bidder1: &signer, bidder2: &signer, bidder3: &signer) {
        Dfinance::register_coin<ETH>(std_acc, b"eth", 18);
        Dfinance::register_coin<BTC>(std_acc, b"btc", 10);

        let (eth_balance, btc_balance) = Steps::mint_coins_and_put_them_to_sender_balance(usr_one, usr_two);
        Debug::print<u128>(&eth_balance);
        Debug::print<u128>(&btc_balance);

        Steps::give_some_etherium_to_bidders(bidder1, bidder2, bidder3);

        Oracle::init_price<ETH, BTC>(std_acc, 100000000);
        Oracle::init_price<BTC, ETH>(std_acc, 10000);

        //        CDP::create_offer<ETH, BTC>(
//            usr_one,
//            Account::withdraw_from_sender<ETH>(usr_one, 100000),
//            120,
//            110
//        );
        //
//        CDP::take_offer<ETH, BTC>(
//            usr_two,
//            Signer::address_of(usr_one)
//        );
//
//        let usr_two_balance = Account::balance<BTC>(usr_two);
//
//        Debug::print<u128>(&usr_two_balance);

        //        {
//            Account::deposit_to_sender<ETH>(&usr_bid1, Dfinance::mint<ETH>(1000000));
//            Account::deposit_to_sender<ETH>(&usr_bid2, Dfinance::mint<ETH>(1000000));
//            Account::deposit_to_sender<ETH>(&usr_bid3, Dfinance::mint<ETH>(1000000));
//        };

        //        let std_acc = Account::create_signer(0x1);
//        let usr_one = Account::create_signer(0x2);
//        let usr_two = Account::create_signer(0x2);
//
//        let usr_bid1 = Account::create_signer(0x11);
//        let usr_bid2 = Account::create_signer(0x12);
//        let usr_bid3 = Account::create_signer(0x13);
//

        // Step 1:
        // - register coins
        // - mint coins
        // - put them to sender balance
        // - print resulting balance
//        {
//            Dfinance::register_coin<ETH>(&std_acc, b"eth", 18);
//            Dfinance::register_coin<BTC>(&std_acc, b"btc", 10);
//
//            let eth = Dfinance::mint<ETH>(10000000000000);
//            let btc = Dfinance::mint<BTC>(10000000000000);
//
//            Account::deposit_to_sender<ETH>(&usr_one, eth);
//            Account::deposit_to_sender<BTC>(&usr_two, btc);
//
//            let eth_balance = Account::balance<ETH>(&usr_one);
//            let btc_balance = Account::balance<BTC>(&usr_two);
//
//            Debug::print<u128>(&eth_balance);
//            Debug::print<u128>(&btc_balance);
//        };


        //        // Step 1.1 Give some Ethereum to bidders
//        {
//            Account::deposit_to_sender<ETH>(&usr_bid1, Dfinance::mint<ETH>(1000000));
//            Account::deposit_to_sender<ETH>(&usr_bid2, Dfinance::mint<ETH>(1000000));
//            Account::deposit_to_sender<ETH>(&usr_bid3, Dfinance::mint<ETH>(1000000));
//        };
//
//        // Step 2:
//        // - mock oracle prices
//        {
//            Oracle::init_price<ETH, BTC>(&std_acc, 100000000);
//            Oracle::init_price<BTC, ETH>(&std_acc, 10000);
//        };
//
//        // Step 3
//        // - usr_one has ETH
//        // - usr_two has BTC
//        // - they can do collateral deal, right?
//        {
//            // offer ETH for BTC.
//            // Offered: 100 000 Wei,
//            // For: 120% BTC
//            // MC at: 110%
//            CDP::create_offer<ETH, BTC>(
//                &usr_one,
//                Account::withdraw_from_sender<ETH>(&usr_one, 100000),
//                120,
//                110
//            );
//
//            CDP::take_offer<ETH, BTC>(
//                &usr_two,
//                Signer::address_of(&usr_one)
//            );
//
//            let usr_two_balance = Account::balance<BTC>(&usr_two);
//
//            Debug::print<u128>(&usr_two_balance);
//        };
//
//        // Step 4:
//        // - oracle price changed
//        // - margin call reached
//        {
//            Oracle::set_price<ETH, BTC>(90000000);
//
//            let deal_status = CDP::check_deal<ETH, BTC>(Signer::address_of(&usr_two));
//            Debug::print<u8>(&deal_status);
//
//            Oracle::set_price<ETH, BTC>(70000000);
//
//            let deal_status = CDP::check_deal<ETH, BTC>(Signer::address_of(&usr_two));
//
//            assert(deal_status == 1, 401);
//
//            Debug::print<u8>(&deal_status);
//
//            let (
//                margin_call_at,
//                current_rate,
//                collateral_amt,
//                offered_amt
//            ) = CDP::get_deal_details<ETH, BTC>(Signer::address_of(&usr_two));
//
//            Debug::print<u128>(&margin_call_at);
//            Debug::print<u128>(&current_rate);
//            Debug::print<u128>(&collateral_amt);
//            Debug::print<u128>(&offered_amt);
//
//            // Deal is not profitable for lender if Offered->Collateral price goes UP /^
//
//            Oracle::set_price<ETH, BTC>(110000000);
//
//            let deal_status = CDP::check_deal<ETH, BTC>(Signer::address_of(&usr_two));
//
//            Debug::print<u8>(&deal_status);
//
//            assert(deal_status == 2, 402);
//        };
//
//        // Step 5:
//        // - lender closes the deal and puts CDP on the auction
//        {
//            CDP::finish_and_create_auction<ETH, BTC>(&usr_one, Signer::address_of(&usr_two));
//
//            // And the auction begins!
//
//            let (
//                start_price,
//                lot,
//                max_bid
//            ) = Auction::get_details<BTC, ETH>(Signer::address_of(&usr_one));
//
//            {
//                Debug::print<u128>(&start_price);
//                Debug::print<u128>(&lot);
//                Debug::print<u128>(&max_bid);
//            };
//
//            // Time for bets
//
//            // Bet 1 -> for starting price
//            {
//                Auction::place_bid<BTC, ETH>(
//                    &usr_bid1,
//                    Signer::address_of(&usr_one),
//                    Account::withdraw_from_sender<ETH>(&usr_bid1, start_price)
//                );
//
//                let (_, _, max_bid) = Auction::get_details<BTC, ETH>(Signer::address_of(&usr_one));
//                let usr_bid1_balance = Account::balance<ETH>(&usr_bid1);
//
//                Debug::print<bool>(&true);
//                Debug::print<u128>(&max_bid);
//                Debug::print<u128>(&usr_bid1_balance);
//            };
//
//            // Bet 2 - for twice larger price
//            {
//                Auction::place_bid<BTC, ETH>(
//                    &usr_bid2,
//                    Signer::address_of(&usr_one),
//                    Account::withdraw_from_sender<ETH>(&usr_bid2, start_price * 2)
//                );
//
//                let (_, _, max_bid) = Auction::get_details<BTC, ETH>(Signer::address_of(&usr_one));
//                let usr_bid1_balance = Account::balance<ETH>(&usr_bid1);
//                let usr_bid2_balance = Account::balance<ETH>(&usr_bid2);
//
//                Debug::print<bool>(&true);
//                Debug::print<u128>(&max_bid);
//                Debug::print<u128>(&usr_bid1_balance);
//                Debug::print<u128>(&usr_bid2_balance);
//            };
//
//            // Bet 3 - for 4-times larger price
//            {
//                Auction::place_bid<BTC, ETH>(
//                    &usr_bid3,
//                    Signer::address_of(&usr_one),
//                    Account::withdraw_from_sender<ETH>(&usr_bid3, start_price * 4)
//                );
//
//                let (_, _, max_bid) = Auction::get_details<BTC, ETH>(Signer::address_of(&usr_one));
//                let usr_bid2_balance = Account::balance<ETH>(&usr_bid1);
//                let usr_bid3_balance = Account::balance<ETH>(&usr_bid3);
//
//                Debug::print<bool>(&true);
//                Debug::print<u128>(&max_bid);
//                Debug::print<u128>(&usr_bid2_balance);
//                Debug::print<u128>(&usr_bid3_balance);
//            };
//
//            // Time to close the deal. No point in further bidding.
//            {
//                Debug::print<bool>(&true);
//                Debug::print<u128>(&Account::balance<ETH>(&usr_one));
//                // Debug::print<u128>(&Account::balance<BTC>(&usr_bid3));
//
//                Auction::end_auction<BTC, ETH>(&usr_one);
//
//                Debug::print<u128>(&Account::balance<ETH>(&usr_one));
//                Debug::print<u128>(&Account::balance<ETH>(&usr_bid3));
//                Debug::print<u128>(&Account::balance<BTC>(&usr_bid3));
//            };
//        };

        //        Account::destroy_signer(std_acc);
//        Account::destroy_signer(usr_one);
//        Account::destroy_signer(usr_two);
//
//        Account::destroy_signer(usr_bid1);
//        Account::destroy_signer(usr_bid2);
//        Account::destroy_signer(usr_bid3);

    }
}


// script {
//     use 0x1::Debug;
//     use 0x1::Account;
//     use 0x2::CDP;
//     use 0x2::Auction;

//     use 0x2::Oracle;
//     use 0x1::Coins::{ETH, BTC, USDT};

//     const SUPPLY : u128 = 100;
//     const DECIMALS : u8 = 8;

//     fun main(account: &signer) {

//         let _ = account;

//         Oracle::init_price<Tok::T<Tok1>, Tok::T<Tok2>>(account, 100000000);
//         Oracle::init_price<Tok::T<Tok2>, Tok::T<Tok1>>(account, 1);

//         Debug::print<u8>(&(10));

//         // Create 2 currencies here, okay???
//         Tok::initialize<Tok1>(account, SUPPLY, DECIMALS, b"tok_1");
//         Tok::initialize<Tok2>(account, SUPPLY, DECIMALS + 2, b"tok_2");

//         CDP::create_offer<
//             Tok::T<Tok1>,
//             Tok::T<Tok2>,
//         >(
//             account,
//             Account::withdraw_from_sender<Tok::T<Tok1>>(account, 10),
//             120,
//             110
//         );

//         CDP::take_offer<
//             Tok::T<Tok1>,
//             Tok::T<Tok2>
//         >(
//             account,
//             0x2
//         );

//         Oracle::set_price<Tok::T<Tok1>, Tok::T<Tok2>>(110000000);
//         Debug::print<u8>(&CDP::check_deal<Tok::T<Tok1>, Tok::T<Tok2>>(0x2));


//         // Auction time!

//         CDP::finish_and_create_auction<Tok::T<Tok1>, Tok::T<Tok2>>(account, 0x2);
//         let res = Auction::has_auction<Tok::T<Tok1>, Tok::T<Tok2>>(0x2);
//         Debug::print<bool>(&res);


//         Debug::print<bool>(&CDP::has_offer<Tok::T<Tok1>, Tok::T<Tok2>>(0x2));
//         Debug::print<u128>(
//             &Account::balance<Tok::T<Tok1>>(account)
//         );

//         Debug::print<u128>(
//             &Account::balance<Tok::T<Tok2>>(account)
//         );
//     }
// }
