// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./NodeRewardController.sol";
import "./interfaces/IJoeRouter02.sol";
import "./interfaces/IJoeFactory.sol";

/**
 * @title SafeMathUint
 * @dev Math operations with safety TKNcks that revert on error
 */
library SafeMathUint {
    function toInt256Safe(uint256 a) internal pure returns (int256) {
        int256 b = int256(a);
        require(b >= 0, "toInt256Safe: B LESS THAN ZERO");
        return b;
    }
}

/**
 * @title SafeMathInt
 * @dev Math operations for int256 with overflow safety TKNcks.
 */
library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    /**
     * @dev Multiplies two int256 variables and fails on overflow.
     */
    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        // Detect overflow when multiplying MIN_INT256 with -1
        require(
            c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256),
            "mul: A B C combi values invalid with MIN_INT256"
        );
        require((b == 0) || (c / b == a), "mul: A B C combi values invalid");
        return c;
    }

    /**
     * @dev Division of two int256 variables and fails on overflow.
     */
    function div(int256 a, int256 b) internal pure returns (int256) {
        // Prevent overflow when dividing MIN_INT256 by -1
        require(b != -1 || a != MIN_INT256, "div: b == 1 OR A == MIN_INT256");

        // Solidity already throws when dividing by 0.
        return a / b;
    }

    /**
     * @dev Subtracts two int256 variables and fails on overflow.
     */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require(
            (b >= 0 && c <= a) || (b < 0 && c > a),
            "sub: A B C combi values invalid"
        );
        return c;
    }

    /**
     * @dev Adds two int256 variables and fails on overflow.
     */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require(
            (b >= 0 && c >= a) || (b < 0 && c < a),
            "add: A B C combi values invalid"
        );
        return c;
    }

    /**
     * @dev Converts to absolute value, and fails on overflow.
     */
    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256, "abs: A EQUAL MIN INT256");
        return a < 0 ? -a : a;
    }

    function toUint256Safe(int256 a) internal pure returns (uint256) {
        require(a >= 0, "toUint256Safe: A LESS THAN ZERO");
        return uint256(a);
    }
}

contract EasyToken is ERC20, Ownable {
    using SafeMath for uint256;

    NodeRewardController private nodeRewardManager;

    IJoeRouter02 public uniswapV2Router;

    address public uniswapV2Pair;
    address public expensePool;
    address public distributionPool;

    address public marketingPool;
    address public treasuryPool;
    address public cashoutPool;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public expenseFee;
    uint256 public totalFees;

    uint256 public sellFee;

    uint256 public marketingFee;

    uint256 private rwSwap;
    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount = 300 * 10 ** 18; // 300 $EASY

    uint256 TOTAL_SUPPLY = 10 ** 12 * (10 ** 18); // 1T $EASY

    mapping(address => bool) public _isBlacklisted;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping (address => bool) private _isExcludedFromFee;

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(
        address indexed newLiquidityWallet,
        address indexed oldLiquidityWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    constructor(
        address[] memory addresses,
        address joeRouterV2Address,
        address nodeControllerAddress
    ) ERC20("EasyToken", "EASY") {

        require(addresses.length == 5, "Count of Addresses must be 5");

        nodeRewardManager = NodeRewardController(nodeControllerAddress);

        treasuryPool = addresses[0];
        distributionPool = addresses[1];
        marketingPool = addresses[2];
        expensePool = addresses[3];
        cashoutPool = addresses[4];

        for (uint256 i = 0; i < 5; i++) {
            _isExcludedFromFee[addresses[i]] = true;
        }

        require(expensePool != address(0) && distributionPool != address(0), "FUTUR & REWARD ADDRESS CANNOT BE ZERO");
        
        rewardsFee = 60;
        liquidityPoolFee = 30;
        marketingFee = 5;
        expenseFee = 5;
        rwSwap = 30;

        totalFees = rewardsFee.add(liquidityPoolFee).add(expenseFee).add(marketingFee);

        _mint(treasuryPool, TOTAL_SUPPLY * 60 / 100); // 60% -> treasury wallet
        _mint(distributionPool, TOTAL_SUPPLY * 20 / 100); // 20 % -> distribution wallet
        _mint(marketingPool, TOTAL_SUPPLY * 20 / 100); // 20% -> marketing wallet 

        uniswapV2Router = IJoeRouter02(joeRouterV2Address);

        uniswapV2Pair = IJoeFactory(uniswapV2Router.factory())
        .createPair(address(this), uniswapV2Router.WAVAX());
        
    }

    function setNodeManagement(address nodeManagement) external onlyOwner {
        nodeRewardManager = NodeRewardController(nodeManagement);
    }

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateExpenseWall(address payable wall) external onlyOwner {
        expensePool = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        distributionPool = wall;
    }

    function updateMarketingWall(address payable wall) external onlyOwner {
        marketingPool = wall;
    }

    function updateCashoutWall(address payable wall) external onlyOwner {
        cashoutPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(expenseFee).add(marketingFee);
    }

    function updateLiquiditFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(expenseFee).add(marketingFee);
    }

    function updateFuturFee(uint256 value) external onlyOwner {
        expenseFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(expenseFee).add(marketingFee);
    }

    function updateMarketingFee(uint256 value) external onlyOwner {
        marketingFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(expenseFee).add(marketingFee);
    }

    function updateSellFee(uint256 value) external onlyOwner {
        sellFee = value;
    }

    function updateRwSwapFee(uint256 value) external onlyOwner {
        rwSwap = value;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
    external
    onlyOwner
    {
        require(
            pair != uniswapV2Pair,
            "TKN: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function blacklistMalicious(address account, bool value)
    external
    onlyOwner
    {
        _isBlacklisted[account] = value;
    }

    function setExcludedFromFee(address account, bool value) external onlyOwner
    {
        _isExcludedFromFee[account] = value;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "Blacklisted address");

        uint256 feeAmount = 0;
        uint256 _amount;

        if (!_isExcludedFromFee[from] && (to == address(uniswapV2Router) || to == address(uniswapV2Pair))) {
            require(nodeRewardManager._isNodeOwner(from), "Create at least one Brain!");

            feeAmount = amount.mul(sellFee).div(100);
        }

        _amount = amount.sub(feeAmount);

        super._transfer(from, cashoutPool, feeAmount);
        super._transfer(from, to, _amount);
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance).sub(initialETHBalance);
        payable(destination).transfer(newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WAVAX();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityAVAX{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    function createNodeWithTokens(string memory name) public {
        require(
            bytes(name).length > 3 && bytes(name).length < 32,
            "NODE CREATION: NAME SIZE INVALID"
        );
        address sender = _msgSender();
        require(
            sender != address(0),
            "NODE CREATION:  creation from the zero address"
        );
        require(!_isBlacklisted[sender], "NODE CREATION: Blacklisted address");
        require(
            sender != expensePool && sender != distributionPool,
            "NODE CREATION: futur and rewardsPool cannot create node"
        );
        uint256 nodePrice = nodeRewardManager.nodePrice();
        require(
            balanceOf(sender) >= nodePrice,
            "NODE CREATION: Balance too low for creation."
        );
        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (
            swapAmountOk &&
            swapLiquify &&
            !swapping &&
            sender != owner() &&
            !automatedMarketMakerPairs[sender]
        ) {
            swapping = true;

            uint256 futurTokens = contractTokenBalance.mul(expenseFee).div(100);

            swapAndSendToFee(expensePool, futurTokens);

            uint256 rewardsPoolTokens = contractTokenBalance
            .mul(rewardsFee)
            .div(100);

            uint256 rewardsTokenstoSwap = rewardsPoolTokens.mul(rwSwap).div(
                100
            );

            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(
                address(this),
                distributionPool,
                rewardsPoolTokens.sub(rewardsTokenstoSwap)
            );

            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);

            uint256 marketingTokens = contractTokenBalance.mul(marketingFee).div(100);

            swapAndSendToFee(marketingPool, marketingTokens);

            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice);
        nodeRewardManager.createNode(sender, name);
    }

    function cashoutReward(uint256 blocktime) external {
        address sender = _msgSender();
        require(sender != address(0), "CSHT:  creation from the zero address");
        require(!_isBlacklisted[sender], "MANIA CSHT: Blacklisted address");
        require(
            sender != expensePool && sender != distributionPool,
            "CSHT: futur and rewardsPool cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(
            sender,
            blocktime
        );
        require(
            rewardAmount > 0,
            "CSHT: You don't have enough reward to cash out"
        );

        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutNodeReward(sender, blocktime);
    }

    function cashoutAll() public {
        address sender = _msgSender();
        require(
            sender != address(0),
            "MANIA CSHT:  creation from the zero address"
        );
        require(!_isBlacklisted[sender], "MANIA CSHT: Blacklisted address");
        require(
            sender != expensePool && sender != distributionPool,
            "MANIA CSHT: future and rewardsPool cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender);
        require(
            rewardAmount > 0,
            "MANIA CSHT: You don't have enough reward to cash out"
        );

        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutAllNodesReward(sender);
    }

    function toString(uint256 value) internal pure returns (bytes memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return buffer;
    }

    function compound(uint256 amount) external {
        require(amount > 0, "CMPD: Amount can't be zero");

        uint256 nodePrice = nodeRewardManager.nodePrice();

        require(amount % nodePrice == 0, "CMPD: Amount must be a multiple of the node price");

        uint256 count = amount / nodePrice;
        uint256 i;
        string memory name;
        bytes memory basic;
        address sender = _msgSender();

        cashoutAll();

        require(balanceOf(_msgSender()) >= amount, "CMPD: Balance is not enough");

        basic = bytes.concat("BRAIN-", toString(block.timestamp), toString(nodeRewardManager._getNodeNumberOf(sender)));

        for (i = 1; i <= count; i++) {
          name = string(bytes.concat(basic, toString(i)));
          createNodeWithTokens(name);
        }
    }

    function renameNode(string memory oldName, string memory newName) external {
      require(
        nodeRewardManager._isNodeOwner(_msgSender()),
        "NO NODE OWNER"
      );

      require(
        bytes(newName).length > 3 && bytes(newName).length < 32,
        "NODE RENAME: NAME SIZE INVALID"
      );

      nodeRewardManager._renameNode(_msgSender(), oldName, newName);
    }

    function boostReward(uint amount) external onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    function changeSwapLiquify(bool newVal) external onlyOwner {
        swapLiquify = newVal;
    }

    function getNodeNumberOf(address account) public view returns (uint256) {
        return nodeRewardManager._getNodeNumberOf(account);
    }

    function getRewardAmountOf(address account)
    public
    view
    onlyOwner
    returns (uint256)
    {
        return nodeRewardManager._getRewardAmountOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManager._isNodeOwner(_msgSender()),
            "NO NODE OWNER"
        );
        return nodeRewardManager._getRewardAmountOf(_msgSender());
    }

    function changeNodePrice(uint256 newNodePrice) external onlyOwner {
        nodeRewardManager._changeNodePrice(newNodePrice);
    }

    function getNodePrice() public view returns (uint256) {
        return nodeRewardManager.nodePrice();
    }

    function changeRewardPerNode(uint256 newPrice) external onlyOwner {
        nodeRewardManager._changeRewardPerNode(newPrice);
    }

    function getRewardPerNode() public view returns (uint256) {
        return nodeRewardManager.rewardPerNode();
    }

    function changeClaimTime(uint256 newTime) external onlyOwner {
        nodeRewardManager._changeClaimTime(newTime);
    }

    function getClaimTime() public view returns (uint256) {
        return nodeRewardManager.claimTime();
    }

    function changeAutoDistri(bool newMode) external onlyOwner {
        nodeRewardManager._changeAutoDistri(newMode);
    }

    function getAutoDistri() public view returns (bool) {
        return nodeRewardManager.autoDistri();
    }

    function changeGasDistri(uint256 newGasDistri) external onlyOwner {
        nodeRewardManager._changeGasDistri(newGasDistri);
    }

    function getGasDistri() public view returns (uint256) {
        return nodeRewardManager.gasForDistribution();
    }

    function getDistriCount() public view returns (uint256) {
        return nodeRewardManager.lastDistributionCount();
    }

    function getNodesNames() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManager._isNodeOwner(_msgSender()),
            "NO NODE OWNER"
        );
        return nodeRewardManager._getNodesNames(_msgSender());
    }

    function getNodesCreatime() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManager._isNodeOwner(_msgSender()),
            "NO NODE OWNER"
        );
        return nodeRewardManager._getNodesCreationTime(_msgSender());
    }

    function getNodesRewards() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManager._isNodeOwner(_msgSender()),
            "NO NODE OWNER"
        );
        return nodeRewardManager._getNodesRewardAvailable(_msgSender());
    }

    function getNodesLastClaims() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(
            nodeRewardManager._isNodeOwner(_msgSender()),
            "NO NODE OWNER"
        );
        return nodeRewardManager._getNodesLastClaimTime(_msgSender());
    }

    function transferNode(address to, string memory nodeName) external returns (bool) {
        return nodeRewardManager._transferNode(msg.sender, to, nodeName);
    }

    function getTotalStakedReward() public view returns (uint256) {
        return nodeRewardManager.totalRewardStaked();
    }

    function getTotalCreatedNodes() public view returns (uint256) {
        return nodeRewardManager.totalNodesCreated();
    }
}