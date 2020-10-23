address 0x1 {
/// Auction is a contract for selling assets in the given
/// interval of time (or possible implementation - when top bid is reached)
/// Scheme is super easy:
/// 1. owner places an asset for starting price in another asset.
/// Currently the only possible asset type is Dfinance::T - a registered coin.
/// 2. bidders place their bids which are stored inside Auction::T resource
/// highest bidder wins when auction is closed by its owner
/// 3. owner takes the bid and bidder gets the asset
///
/// Optional TODOs:
/// - set optional minimal step size (say, 10000 units)
/// - add error codes for operations in this contract
/// - add end strategy - by time or by reaching the max value
module Auction {

    use 0x1::Dfinance;
    use 0x1::Account;
    use 0x1::Signer;
    use 0x1::Event;

    /// Resource of the Auction. Stores max_bid and the bidder
    /// address for sending asset back or rewarding the winner.
    resource struct T<Lot, For> {
        lot: Dfinance::T<Lot>,
        max_bid: Dfinance::T<For>,
        start_price: u128,
        bidder: address,
        ends_at: u64
    }

    struct AuctionCreatedEvent<Lot, For> {
        owner: address,
        ends_at: u64,
        lot_amount: u128,
        start_price: u128,
    }

    struct BidPlacedEvent<Lot, For> {
        owner: address,
        bidder: address,
        bid_amount: u128
    }

    struct AuctionEndEvent<Lot, For> {
        owner: address,
        bidder: address,
        bid_amount: u128
    }

    /// Create Auction resource under Owner (sender) address
    /// Set default bidder as owner, max bid to 0 and start_price
    public fun create<Lot: copyable, For: copyable>(
        account: &signer,
        start_price: u128,
        lot: Dfinance::T<Lot>,
        ends_at: u64
    ) {
        let owner = Signer::address_of(account);
        let lot_amount = Dfinance::value(&lot);

        move_to<T<Lot, For>>(account, T {
            lot,
            ends_at,
            start_price,
            max_bid: Dfinance::zero<For>(),
            bidder: owner
        });

        Event::emit<AuctionCreatedEvent<Lot, For>>(
            account,
            AuctionCreatedEvent {
                owner,
                ends_at,
                lot_amount,
                start_price,
            }
        );
    }

    /// Check whether someone has published an auction for specific ticker
    public fun has_auction<Lot, For>(owner: address): bool {
        exists<T<Lot, For>>(owner)
    }

    /// Get offered amount and max bid at the time
    public fun get_details<Lot, For>(
        owner: address
    ): (u128, u128, u128) acquires T {
        let auction = borrow_global<T<Lot, For>>(owner);

        (
            auction.start_price,
            Dfinance::value(&auction.lot),
            Dfinance::value(&auction.max_bid)
        )
    }

    /// Place a bid for specific auction at address.
    /// What's a bit complicated is sending previous bid to its owner.
    /// But looks like there is a solution at the moment.
    public fun place_bid<Lot: copyable, For: copyable>(
        account: &signer,
        auction_owner: address,
        bid: Dfinance::T<For>
    ) acquires T {

        let bidder  = Signer::address_of(account);
        let auction = borrow_global_mut<T<Lot, For>>(auction_owner);
        let bid_amt = Dfinance::value(&bid);
        let max_bid = Dfinance::value(&auction.max_bid);

        assert(bid_amt > max_bid, 1);
        assert(bidder != auction.bidder, 1);
        assert(bid_amt >= auction.start_price, 1);

        // in case it's not empty bid by lender
        if (max_bid > 0) {
            let to_send_back = Dfinance::withdraw(&mut auction.max_bid, max_bid);
            Account::deposit<For>(account, auction.bidder, to_send_back);
        };

        // zero is left, filling with new bid
        Dfinance::deposit(&mut auction.max_bid, bid);

        // and changing the owner of current bid
        auction.bidder = bidder;

        Event::emit<BidPlacedEvent<Lot, For>>(
            account,
            BidPlacedEvent {
                bidder,
                owner: auction_owner,
                bid_amount: bid_amt
            }
        );
    }

    /// End auction: destroy resource, give lot to bidder and bid to owner
    public fun end_auction<Lot: copyable, For: copyable>(
        account: &signer
    ) acquires T {

        let owner = Signer::address_of(account);

        let T {
            lot,
            bidder,
            max_bid,
            ends_at: _,
            start_price: _,
        } = move_from<T<Lot, For>>(owner);

        let bid_amount = Dfinance::value(&max_bid);

        Account::deposit_to_sender(account, max_bid);
        Account::deposit(account, bidder, lot);

        Event::emit<AuctionEndEvent<Lot, For>>(
            account,
            AuctionEndEvent {
                owner,
                bidder,
                bid_amount
            }
        );
    }
}
}
