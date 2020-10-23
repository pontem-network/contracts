address 0x1 {
// Final thoughts on CDP implementation
// 1. Resulting currency must be "cut" to its decimals
// 2. Decimals for deal are decided by formula: MIN(8, CURR1dec, CURR2dec).
//

// DEPRECATED.
// WHOOPSIE-DOOPSIE.

// 1. sXFI
// 2. CDP

// - 1 | 2 | 1 - //
// - 2 | 1 | 2 - //

// CDP - exchange ETH for sXFI - OVER COLLATERIZED DEAL;
// Can be refilled, can be returned (deal is closed);
// Can be turned into CDS;
//
// User can choose his collateral and choose how much money he wants
// Can refill;

module CDP {
//    use 0x1::Auction;
    use 0x1::Coins;
    use 0x1::Dfinance;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Event;

    const ORACLE_DECIMALS: u8 = 8;

    const ERR_DEAL_IS_OKAY: u64 = 200;
    const ERR_NO_RATE: u64 = 401;
    const ERR_NOT_LENDER: u64 = 402;
    const ERR_INCORRECT_ARGUMENT: u64 = 400;

    const DEAL_NOT_MADE: u8 = 0;
    const DEAL_OKAY: u8 = 1;
    const DEAL_PAST_MARGIN_CALL: u8 = 2;

    /// CDP resource
    resource struct T<Offered, Collateral> {
        offered_amount: u128,
        collateral: Dfinance::T<Collateral>,
        margin_call_rate: u128,
        current_rate: u128,
        lender: address
    }

    struct OfferTakenEvent<Offered, Collateral> {
        offered_amount: u128,
        collateral_amount: u128,
        margin_call_rate: u128,
        current_rate: u128,
        borrower: address,
        lender: address
    }

    struct OfferCreatedEvent<Offered, Collateral> {
        offered_amount: u128,
        margin_call_at: u8,
        collateral_multiplier: u8,
        lender: address
    }

    struct OfferCancelledEvent<Offered, Collateral> {
        lender: address
    }

    struct OfferClosedEvent<Offered, Collateral> {
        borrower: address,
        lender: address,
        current_rate: u128,
        offered_amount: u128,
        margin_call_rate: u128,
        initiative: address
    }

    public fun finish_and_release_funds<
        Offered: copyable,
        Collateral: copyable
    >(
        account: &signer,
        borrower: address
    ) acquires T {
        let deal_status = check_deal<Offered, Collateral>(borrower);

        assert(deal_status == DEAL_PAST_MARGIN_CALL, ERR_DEAL_IS_OKAY);

        let T {
            lender,
            collateral,
            offered_amount,
            current_rate: _,
            margin_call_rate,
        } = move_from<T<Offered, Collateral>>(borrower);

        assert(Signer::address_of(account) == lender, ERR_NOT_LENDER);

        // deposit()
        Account::deposit_to_sender<Collateral>(account, collateral);

        let current_rate = Coins::get_price<Offered, Collateral>();

        Event::emit<OfferClosedEvent<Offered, Collateral>>(
            account,
            OfferClosedEvent {
                lender,
                borrower,
                current_rate,
                offered_amount,
                margin_call_rate,
                initiative: lender
            }
        );
    }

    public fun return_money<
        Offered: copyable,
        Collateral: copyable
    >(
        account: &signer
    ) acquires T {
        let borrower = Signer::address_of(account);
        let deal_status = check_deal<Offered, Collateral>(borrower);

        assert(deal_status == DEAL_OKAY, 0); // TODO: ERROR CODE HERE

        let T {
            lender,
            collateral,
            current_rate,
            offered_amount,
            margin_call_rate,
        } = move_from<T<Offered, Collateral>>(borrower);

        let borrower_balance = Account::balance<Offered>(account);

        assert(borrower_balance >= offered_amount, 0); // TODO: ERROR STATUS HERE!!!!

        Account::deposit_to_sender<Collateral>(account, collateral);
        Account::pay_from_sender<Offered>(account, lender, offered_amount);

        // Deal is done. Resource no longer exists,

        Event::emit<OfferClosedEvent<Offered, Collateral>>(
            account,
            OfferClosedEvent {
                lender,
                borrower,
                current_rate,
                offered_amount,
                margin_call_rate,
                initiative: borrower
            }
        );
    }

    public fun get_deal_details<Offered, Collateral>(
        borrower: address
    ): (u128, u128, u128, u128) acquires T {
        let deal = borrow_global<T<Offered, Collateral>>(borrower);

        (
            deal.margin_call_rate,
            deal.current_rate,
            Dfinance::value(&deal.collateral),
            deal.offered_amount
        )
    }

    public fun check_deal<Offered, Collateral>(
        borrower: address
    ): u8 acquires T {
        if (!exists<T<Offered, Collateral>>(borrower)) {
            return DEAL_NOT_MADE
        };

        let cdp_deal = borrow_global<T<Offered, Collateral>>(borrower);
        let rate = Coins::get_price<Offered, Collateral>();

        if (rate >= cdp_deal.margin_call_rate) {
            return DEAL_PAST_MARGIN_CALL
        };

        DEAL_OKAY
    }

    /// This method automatically takes money from balance of the
    /// borrower (right amount) and creates a deal placed on borrower's
    /// account.
    /// WARNING: This operation uses unprecise calculations due to the
    ///          limitations of u128 which can be overflown.
    ///
    /// Kind copyable is put intentionally, since all known coins have to
    /// be of Copyable kind. See 0x1::Coins;
    public fun take_offer<
        Offered: copyable,
        Collateral: copyable
    >(
        account: &signer,
        lender: address
    ) acquires Offer {
        let Offer {
            offered,
            collateral_multiplier,
            margin_call_at
        } = move_from<Offer<Offered, Collateral>>(lender);

        // ETH -> BTC

        let rate: u128 = Coins::get_price<Offered, Collateral>();
        let offered_amount = Dfinance::value<Offered>(&offered); // ETH

        // MUL((1000000, 18), (10000000, 8), 18);

        // ETH * ETH->BTC * 120 / 100 / 10^8
        let to_pay = offered_amount * (rate as u128) * (collateral_multiplier as u128) / 100 / 100000000;
        let margin_call_rate = rate * (margin_call_at as u128) / 100;
        let collateral = Account::withdraw_from_sender<Collateral>(account, to_pay);

        Account::deposit_to_sender<Offered>(account, offered);

        move_to<T<Offered, Collateral>>(account, T {
            lender,
            collateral,
            offered_amount,
            margin_call_rate,
            current_rate: rate
        });

        Event::emit<OfferTakenEvent<Offered, Collateral>>(
            account,
            OfferTakenEvent {
                lender,
                offered_amount,
                margin_call_rate,
                current_rate: rate,
                collateral_amount: to_pay,
                borrower: Signer::address_of(account),
            }
        );
    }

    /// CDP offer created by lender
    resource struct Offer<Offered, Collateral> {
        offered: Dfinance::T<Offered>,
        collateral_multiplier: u8,
        margin_call_at: u8
    }

    /// Creates a CDP deal
    public fun create_offer<
        Offered: copyable,
        Collateral: copyable
    >(
        account: &signer,
        offered: Dfinance::T<Offered>,
        collateral_multiplier: u8, // percent value * 100
        margin_call_at: u8         // percent value * 100
) {
        let offered_amount = Dfinance::value<Offered>(&offered);

        assert(Coins::has_price<Offered, Collateral>(), ERR_NO_RATE);
        assert(offered_amount > 0, ERR_INCORRECT_ARGUMENT);

        // make sure that collateral mult is greater than 100 and
        // is greater than margin call (that's a must!)
        assert(
            collateral_multiplier > margin_call_at
                    && collateral_multiplier > 100
            , ERR_INCORRECT_ARGUMENT);

        move_to<Offer<Offered, Collateral>>(
            account,
            Offer {
                offered,
                collateral_multiplier,
                margin_call_at
            }
        );

        Event::emit<OfferCreatedEvent<Offered, Collateral>>(
            account,
            OfferCreatedEvent {
                offered_amount,
                margin_call_at,
                collateral_multiplier,
                lender: Signer::address_of(account)
            }
        );
    }

    /// Check whether account has offer for given currency pairs
    public fun has_offer<Offered, Collateral>(account: address): bool {
        exists<Offer<Offered, Collateral>>(account)
    }

    /// Get tuple with offer details such as collateral_amount and margin_call
    public fun get_offer_details<Offered, Collateral>(account: address): (u128, u8, u8) acquires Offer {
        let offer = borrow_global<Offer<Offered, Collateral>>(account);

        (
            Dfinance::value<Offered>(&offer.offered),
            offer.collateral_multiplier,
            offer.margin_call_at
        )
    }
}
}
