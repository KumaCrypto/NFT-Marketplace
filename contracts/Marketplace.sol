//SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IERC721NFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Marketplace is ReentrancyGuard, Ownable, IERC721Receiver {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;
    Counters.Counter private _totalAmount;

    // Added an additional counter, since _tokenIds can be reduced by burning.
    // And intranal because the marketplace contract will display the total amount.

    Counters.Counter private _itemsSold;

    IERC721 private NFT;
    IERC20 private ERC20Token;

    uint256 private _mintPrice;
    uint256 private _auctionDuration;
    uint256 private _auctionMinimalBidAmount;

    constructor(
        uint256 newPrice,
        uint256 newAuctionDuration,
        uint256 newAuctionMinimalBidAmount
    ) {
        upgradeMintPrice(newPrice);
        setAuctionDuration(newAuctionDuration);
        setAuctionMinimalBidAmount(newAuctionMinimalBidAmount);
    }

    event NFTAddressChanged(address oldAddress, address newAddress);
    event ERC20AddressChanged(address oldAddress, address newAddress);
    event MintPriceUpgraded(uint256 oldPrice, uint256 newPrice, uint256 time);
    event Burned(uint256 indexed tokenId, address sender, uint256 currentTime);
    event EventCanceled(uint256 indexed tokenId, address indexed seller);

    event AuctionMinimalBidAmountUpgraded(
        uint256 newAuctionMinimalBidAmount,
        uint256 time
    );

    event AuctionDurationUpgraded(
        uint256 newAuctionDuration,
        uint256 currentTime
    );

    event MarketItemCreated(
        uint256 indexed itemId,
        address indexed owner,
        uint256 timeOfCreation
    );

    event ListedForSale(
        uint256 indexed itemId,
        uint256 price,
        uint256 listedTime,
        address indexed owner,
        address indexed seller
    );

    event Sold(
        uint256 indexed itemId,
        uint256 price,
        uint256 soldTime,
        address indexed seller,
        address indexed buyer
    );

    event StartAuction(
        uint256 indexed itemId,
        uint256 startPrice,
        address seller,
        uint256 listedTime
    );

    event BidIsMade(
        uint256 indexed tokenId,
        uint256 price,
        uint256 numberOfBid,
        address indexed bidder
    );

    event PositiveEndAuction(
        uint256 indexed itemId,
        uint256 endPrice,
        uint256 bidAmount,
        uint256 endTime,
        address indexed seller,
        address indexed winner
    );

    event NegativeEndAuction(
        uint256 indexed itemId,
        uint256 bidAmount,
        uint256 endTime
    );

    event NFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    enum TokenStatus {
        DEFAULT,
        ACTIVE,
        ONSELL,
        ONAUCTION,
        BURNED
    }

    enum SaleStatus {
        DEFAULT,
        ACTIVE,
        SOLD,
        CANCELLED
    }

    enum AuctionStatus {
        DEFAULT,
        ACTIVE,
        SUCCESSFUL_ENDED,
        UNSUCCESSFULLY_ENDED
    }

    struct SaleOrder {
        address seller;
        address owner;
        uint256 price;
        SaleStatus status;
    }

    struct AuctionOrder {
        uint256 startPrice;
        uint256 startTime;
        uint256 currentPrice;
        uint256 bidAmount;
        address owner;
        address seller;
        address lastBidder;
        AuctionStatus status;
    }

    mapping(uint256 => TokenStatus) private _idToItemStatus;
    mapping(uint256 => SaleOrder) private _idToOrder;
    mapping(uint256 => AuctionOrder) private _idToAuctionOrder;

    modifier isActive(uint256 tokenId) {
        require(
            _idToItemStatus[tokenId] == TokenStatus.ACTIVE,
            "This NFT has already been put up for sale or auction!"
        );
        _;
    }

    modifier AuctionIsActive(uint256 tokenId) {
        require(
            _idToAuctionOrder[tokenId].status == AuctionStatus.ACTIVE,
            "Auction already ended!"
        );
        _;
    }

    function createItem(string memory tokenURI, address owner) external {
        ERC20Token.transferFrom(msg.sender, address(this), _mintPrice);

        _totalAmount.increment();
        _tokenIds.increment();

        uint256 tokenId = _tokenIds.current();

        NFT.mint(owner, tokenId, tokenURI);

        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;
        emit MarketItemCreated(tokenId, owner, block.timestamp);
    }

    function listItem(uint256 tokenId, uint256 price)
        external
        isActive(tokenId)
    {
        address owner = NFT.ownerOf(tokenId);
        NFT.safeTransferFrom(owner, address(this), tokenId);

        _idToItemStatus[tokenId] = TokenStatus.ONSELL;

        _idToOrder[tokenId] = SaleOrder(
            msg.sender,
            owner,
            price,
            SaleStatus.ACTIVE
        );

        emit ListedForSale(tokenId, price, block.timestamp, owner, msg.sender);
    }

    function buyItem(uint256 tokenId) external nonReentrant {
        SaleOrder storage order = _idToOrder[tokenId];
        require(order.status == SaleStatus.ACTIVE, "The token isn't on sale");

        order.status = SaleStatus.SOLD;
        ERC20Token.transferFrom(msg.sender, order.seller, order.price);

        NFT.safeTransferFrom(address(this), msg.sender, tokenId);
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;

        _itemsSold.increment();

        emit Sold(
            tokenId,
            order.price,
            block.timestamp,
            order.seller,
            msg.sender
        );
    }

    function cancel(uint256 tokenId) external nonReentrant {
        SaleOrder storage order = _idToOrder[tokenId];

        require(
            msg.sender == order.owner || msg.sender == order.seller,
            "You don't have the authority to cancel the sale of this token!"
        );
        require(
            _idToOrder[tokenId].status == SaleStatus.ACTIVE,
            "The token wasn't on sale"
        );

        NFT.safeTransferFrom(address(this), order.owner, tokenId);

        order.status = SaleStatus.CANCELLED;
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;

        emit EventCanceled(tokenId, msg.sender);
    }

    function listItemOnAuction(uint256 tokenId, uint256 minPeice)
        external
        isActive(tokenId)
    {
        address owner = NFT.ownerOf(tokenId);
        NFT.safeTransferFrom(owner, address(this), tokenId);

        _idToItemStatus[tokenId] = TokenStatus.ONAUCTION;

        _idToAuctionOrder[tokenId] = AuctionOrder(
            minPeice,
            block.timestamp,
            0,
            0,
            owner,
            msg.sender,
            address(0),
            AuctionStatus.ACTIVE
        );

        emit StartAuction(tokenId, minPeice, msg.sender, block.timestamp);
    }

    function makeBid(uint256 tokenId, uint256 price)
        external
        AuctionIsActive(tokenId)
    {
        AuctionOrder storage order = _idToAuctionOrder[tokenId];

        require(
            price > order.currentPrice && price >= order.startPrice,
            "Your bid less or equal to current bid!"
        );

        if (order.currentPrice != 0) {
            ERC20Token.transfer(order.lastBidder, order.currentPrice);
        }

        ERC20Token.transferFrom(msg.sender, address(this), price);

        order.currentPrice = price;
        order.lastBidder = msg.sender;
        order.bidAmount += 1;

        emit BidIsMade(tokenId, price, order.bidAmount, order.lastBidder);
    }

    function finishAuction(uint256 tokenId)
        external
        AuctionIsActive(tokenId)
        nonReentrant
    {
        AuctionOrder storage order = _idToAuctionOrder[tokenId];

        require(
            order.startTime + _auctionDuration < block.timestamp,
            "Auction duration not complited!"
        );

        if (order.bidAmount < _auctionMinimalBidAmount) {
            _cancelAuction(tokenId);
            emit NegativeEndAuction(tokenId, order.bidAmount, block.timestamp);
            return;
        }

        NFT.safeTransferFrom(address(this), order.lastBidder, tokenId);
        ERC20Token.transfer(order.seller, order.currentPrice);

        order.status = AuctionStatus.SUCCESSFUL_ENDED;
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;

        _itemsSold.increment();
        emit PositiveEndAuction(
            tokenId,
            order.currentPrice,
            order.bidAmount,
            block.timestamp,
            order.seller,
            order.lastBidder
        );
    }

    function cancelAuction(uint256 tokenId) external nonReentrant {
        require(
            msg.sender == _idToAuctionOrder[tokenId].owner ||
                msg.sender == _idToAuctionOrder[tokenId].seller,
            "You don't have the authority to cancel the sale of this token!"
        );
        require(
            _idToAuctionOrder[tokenId].bidAmount == 0,
            "You can't cancel the auction which already has a bidder!"
        );
        _cancelAuction(tokenId);
        emit EventCanceled(tokenId, _idToAuctionOrder[tokenId].seller);
    }

    function _cancelAuction(uint256 tokenId) private {
        _idToAuctionOrder[tokenId].status = AuctionStatus.UNSUCCESSFULLY_ENDED;

        NFT.safeTransferFrom(
            address(this),
            _idToAuctionOrder[tokenId].owner,
            tokenId
        );
        _idToItemStatus[tokenId] = TokenStatus.ACTIVE;

        if (_idToAuctionOrder[tokenId].bidAmount != 0) {
            ERC20Token.transfer(
                _idToAuctionOrder[tokenId].lastBidder,
                _idToAuctionOrder[tokenId].currentPrice
            );
        }
    }

    function burn(uint256 tokenId) external isActive(tokenId) {
        address owner = NFT.ownerOf(tokenId);
        require(owner == msg.sender, "Only owner can burn a token!");

        NFT.burn(tokenId);

        _totalAmount.decrement();
        _idToItemStatus[tokenId] = TokenStatus.BURNED;
        emit Burned(tokenId, msg.sender, block.timestamp);
    }

    function withdrawTokens(address receiver, uint256 amount)
        external
        onlyOwner
    {
        ERC20Token.transfer(receiver, amount);
    }

    function setNFTAddress(address newNFTAddress) external onlyOwner {
        emit NFTAddressChanged(address(NFT), newNFTAddress);
        NFT = IERC721(newNFTAddress);
    }

    function setERC20Token(address newToken) external onlyOwner {
        emit ERC20AddressChanged(address(ERC20Token), newToken);
        ERC20Token = IERC20(newToken);
    }

    function upgradeMintPrice(uint256 _newPrice) public onlyOwner {
        uint256 newPrice = _newPrice;
        emit MintPriceUpgraded(_mintPrice, newPrice, block.timestamp);
        _mintPrice = newPrice;
    }

    function setAuctionDuration(uint256 newAuctionDuration) public onlyOwner {
        _auctionDuration = newAuctionDuration;
        emit AuctionDurationUpgraded(newAuctionDuration, block.timestamp);
    }

    function setAuctionMinimalBidAmount(uint256 newAuctionMinimalBidAmount)
        public
        onlyOwner
    {
        _auctionMinimalBidAmount = newAuctionMinimalBidAmount;
        emit AuctionMinimalBidAmountUpgraded(
            newAuctionMinimalBidAmount,
            block.timestamp
        );
    }

    function getERC20Token() external view returns (address) {
        return address(ERC20Token);
    }

    function getNFT() external view returns (address) {
        return address(NFT);
    }

    function getTokenStatus(uint256 tokenId)
        external
        view
        returns (TokenStatus)
    {
        return _idToItemStatus[tokenId];
    }

    function getSaleOrder(uint256 tokenId)
        external
        view
        returns (SaleOrder memory)
    {
        return _idToOrder[tokenId];
    }

    function getAuctionOrder(uint256 tokenId)
        external
        view
        returns (AuctionOrder memory)
    {
        return _idToAuctionOrder[tokenId];
    }

    function getTotalAmount() public view returns (uint256) {
        return _totalAmount.current();
    }

    function getItemsSold() public view returns (uint256) {
        return _itemsSold.current();
    }

    function getMintPrice() external view returns (uint256) {
        return _mintPrice;
    }

    function getAuctionMinimalBidAmount() external view returns (uint256) {
        return _auctionMinimalBidAmount;
    }

    function getAuctionDuration() external view returns (uint256) {
        return _auctionDuration;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        emit NFTReceived(operator, from, tokenId, data);
        return IERC721Receiver.onERC721Received.selector;
    }
}
