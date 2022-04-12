# NFT Marketplace
## Functional description:
- CreateItem() function - creating a new item, accesses the NFT contract and calls the mint function.
- The mint() function, which only the marketplace contract should have access to
- The ListItem() function is an exhibition for the sale of an item.
- buyItem() function - purchase of an item.
- Cancel() function - canceling the sale of the exhibited item
- The listItemOnAuction() function is an exhibition of an item for sale in an auction.
- makeBid() function - place a bid on an auction item with a specific id.
- finishAuction() function - complete the auction and send the NFT to the winner
- cancelAuction() function - cancel the auction

The auction lasts 3 days from the start of the auction. During this period, the auction cannot be canceled. If more than two bids are collected after the expiration of the period, the auction is considered to have taken place and the auction creator completes it (the NFT passes to the last bidder and tokens to the auction creator). Otherwise, the tokens are returned to the last bidder, and the NFT remains with the creator.

## Deployed in rinkeby:

  Contracts        |                             Addresses                      |
-------------------|------------------------------------------------------------|
  Marketplace      |        0xCEEF5dc5a78f4420Befa8018bD890Fb503B2cb69          |                                            
  Nft              |        0xbF0c0362122C66104633f2bA0622e7838A3d7049          |
