pragma solidity ^0.4.18;

import "./Ownable.sol";

contract ERC20Partial {
    function totalSupply() constant returns (uint totalSupply);
    function balanceOf(address _owner) constant returns (uint balance);
    function transfer(address _to, uint _value) returns (bool success);
    event Transfer(address indexed _from, address indexed _to, uint _value);
}

contract TokenSeller is Ownable {
    address public asset;       //token to be traded
    uint public sellPrice;      //price of the lot
    uint public units;          //lot size

    bool public sellsTokens;    //bool to check if the contract is selling tokens

    event ActivatedEvent(bool sells);           //event trigger to show that a account sells
    event MakerWithdrewAsset(uint256 tokens);   //event trigger when account withdraws a token asset
    event MakerTransferredAsset(address toTokenSeller, uint256 tokens); //event trigger when account transfers a token asset
    event MakerWithdrewERC20Token(address tokenAddress, uint256 tokens); //event trigger when account withdraws an ERC20 compliant token asset
    event MakerWithdrewEther(uint256 ethers);       //event for when seller account withdraws ether from transaction
    event TakerBoughtAsset(address indexed buyer, uint256 ethersSent, uint256 ethersReturned, uint256 tokensBought);    //event for when buyer account purchases token asset

    /** Constructor Method
     * Constructor should only be called by the TokenSellerFactory contract
     * @param _asset address of token asset to be sold for ether
     * @param _sellPrice sales price of lot 
     * @param _units size of lot 
     * @param _sellsTokens validate that TokenSeller contract has permission to sell from Factory
     */
    function TokenSeller(address _asset,uint _sellPrice ,uint _units ,bool _sellsTokens) public {
        asset = _asset;
        sellPrice = _sellPrice;
        units = _units;
        sellsTokens = _sellsTokens;
        ActivatedEvent(sellsTokens);
    }

    /** Activate/Deactivate contract sell status
     * Make of the contract can control sell permission of the contract
     * @param _sellsTokens permission variable
     */
    function activate(bool _sellsTokens) public onlyOwner {
        sellsTokens = _sellsTokens;
        ActivatedEvent(sellsTokens);
    }
    /** Withdraw tokens from Contract
     * Contract Owner can withdraw tokens from the contract, essentially decreasing the order to sell
     * @param tokens amount of tokens to be withdrawn from the contract
     * @return confirm confirmation of withdrawal
     */
    function makerWithdrawAsset(uint tokens) public onlyOwner returns (bool confirm) {
        MakerWithdrewAsset(tokens);
        return ERC20Partial(asset).transfer(owner, tokens);
    }
    /** Return Tokens to Contract Maker
     * Used to return tokens accidentally sent for sale, that is, if the incorrect token type was sent.
     * Only permissable for contract owner to perform reversal
     * @param tokenAddress address of token accidentally sent
     * @param amount amount sent to be reversed
     * @return confirm confirmation to ensure function executed
     */
    function makerWithdrawERC20Token(address tokenAddress, uint amount) public onlyOwner returns (bool confirm) {
        MakerWithdrewERC20Token(tokenAddress, amount);
        return ERC20Partial(tokenAddress).transfer(owner, amount);
    }

    /** Withdraw Ether from Contract
     * Maker can withdraw ether sent to contract for trade. Only can be executed by contract owner.
     * Contract balance is checked to ensure sufficient ether is available for withdrawel.
     * @param amount ether amount to be withdrawn
     * @return confirm transaction confirmation
     */
    function makerWithdrawEther(uint amount) public onlyOwner returns (bool confirm) {
        
        if (this.balance >= amount) {               //check contract balance
            MakerWithdrewEther(amount);
            return owner.send(amount);
        }
        return false;
    }
    /** Taker Purchases Token
     * The taker is able to purchase tokens offered by the contract with thei ether.
     * 
     * TO DO: (1) Remove depreacted 'throw' commands and replace with 'require()' or suitable counterpart
              (2) Fix "else if" parse error
     */
    function takerBuyAsset() payable {
        if (sellsTokens || msg.sender == owner) {
            // Note that sellPrice has already been validated as > 0
            uint order = msg.value / sellPrice;
            // Note that units has already been validated as > 0
            uint can_sell = ERC20Partial(asset).balanceOf(address(this)) / units;
            uint change = 0;
            if (msg.value > (can_sell * sellPrice)) {
                change = msg.value - (can_sell * sellPrice);
                order = can_sell;
            }
            if (change > 0) {
                require(msg.sender.send(change));
            }
            if (order > 0) {
                require(ERC20Partial(asset).transfer(msg.sender, order * units));
            }
            TakerBoughtAsset(msg.sender, msg.value, change, order * units);
        } else {
            // Return user funds if the contract is not selling 
            require(msg.sender.send(msg.value));
        }
    }
    
    /** Fallback function 
     */
    function() payable {
        takerBuyAsset;
    }
}

contract TokenSellerFactory is Ownable {

    event TradeListing(address indexed ownerAddress, address indexed tokenSellerAddress,address indexed asset, uint256 sellPrice, uint256 units, bool sellsTokens);
    event OwnerWithdrewERC20Token(address indexed tokenAddress, uint256 tokens);

    mapping (address => bool) _verify;      //mapping to verify address has a smart contract made by factory

    /** Verify Token Seller Contracts
     * Function is called to verify the parameters of a deployed TokenSeller contract
     * @param tradeContract address of contract to be verified
     *
     * @return  valid        did this TokenTraderFactory create the TokenTrader contract?
     * @return  owner        is the owner of the TokenTrader contract
     * @return  asset        is the ERC20 asset address
     * @return  sellPrice    is the sell price in ethers per `units` of asset tokens
     * @return  units        is the number of units of asset tokens
     * @return  sellsTokens  is the TokenTrader contract selling tokens? 
     */
    function verify(address tradeContract) public returns (bool valid, address owner, address asset, uint sellPrice, uint units, bool sellsTokens) {
        valid = _verify[tradeContract];
        if (valid) {
            TokenSeller t = TokenSeller(tradeContract);
            owner = t.owner();
            asset = t.asset();
            sellPrice = t.sellPrice();
            units = t.units();
            sellsTokens = t.sellsTokens();
        }
    }

    /** Create TokenSeller contract
     * Generates seller smart contracts for use of token sell orders.
     * For example, listing a TokenSeller contract on the network where the 
     * contract will sell H20 tokens at a rate of 170/100000 = 0.0017 ETH per H20 token:
     *    token address   0xa74476443119a942de498590fe1f2454d7d4ac0d
     *    sellPrice       170
     *    units           100000
     *    sellsTokens     true
     * @param token address of token to be traded
     * @param sellPrice price of lot for sale
     * @param units size of a lot
     * @param sellsTokens check if the contract has permission to sell
     */
    function createSaleContract(address token, uint sellPrice, uint units, bool sellsTokens) public returns (address seller) {
        require(token != 0x0);
        require(sellPrice >= 0);
        require(units >= 0);
        seller = new TokenSeller(token, sellPrice, units, sellsTokens);
        _verify[seller] = true;
        TokenSeller(seller).transferOwnership(msg.sender);
        TradeListing(msg.sender, seller, token, sellPrice, units, sellsTokens);
    }

    /** Withdraw any ECR20 token from factory 
     * MAinly used for erroneuos transaction sent to the factory
     *
     */
    function ownerWithdrawERC20Token(address tokenAddress, uint256 tokens) public onlyOwner returns (bool ok) {
        OwnerWithdrewERC20Token(tokenAddress, tokens);
        return ERC20Partial(tokenAddress).transfer(owner, tokens);
    }

    function () {
        throw;
    }

}

