// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] keys;
        mapping(address => uint256) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    function get(Map storage map, address key) internal view returns (uint256) {
        return map.values[key];
    }

    function getIndexOfKey(Map storage map, address key)
    internal
    view
    returns (int256)
    {
        if (!map.inserted[key]) {
            return -1;
        }
        return int256(map.indexOf[key]);
    }

    function getKeyAtIndex(Map storage map, uint256 index)
    internal
    view
    returns (address)
    {
        return map.keys[index];
    }

    function size(Map storage map) internal view returns (uint256) {
        return map.keys.length;
    }

    function set(
        Map storage map,
        address key,
        uint256 val
    ) internal {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(Map storage map, address key) internal {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint256 index = map.indexOf[key];
        uint256 lastIndex = map.keys.length - 1;
        address lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}
contract NodeRewardController {
    using SafeMath for uint256;
    using IterableMapping for IterableMapping.Map;

    struct NodeEntity {
        string name;
        uint256 creationTime;
        uint256 lastClaimTime;
        uint256 rewardAvailable;
    }

    IterableMapping.Map private nodeOwners;
    mapping(address => NodeEntity[]) private _nodesOfUser;

    uint256 public nodePrice;
    uint256 public rewardPerNode;
    uint256 public rewardPerSecond;
    uint256 public claimTime;

    address public gateKeeper;
    address public token;

    bool public autoDistri = true;
    bool public distribution = false;

    uint256 public gasForDistribution = 300000;
    uint256 public lastDistributionCount = 0;
    uint256 public lastIndexProcessed = 0;

    uint256 public totalNodesCreated = 0;
    uint256 public totalRewardStaked = 0;

    constructor(
        uint256 _nodePrice,
        uint256 _rewardPerNode,
        uint256 _claimTime
    ) {
        require(_claimTime != 0, "Claim interval cannot be zero!");
        nodePrice = _nodePrice;
        rewardPerNode = _rewardPerNode;
        claimTime = _claimTime;
        rewardPerSecond = _rewardPerNode / _claimTime;
        gateKeeper = msg.sender;
    }

    modifier onlySentry() {
        require(msg.sender == token || msg.sender == gateKeeper, "Fuck off");
        _;
    }

    function setToken (address token_) external onlySentry {
        token = token_;
    }

    function createNode(address account, string memory nodeName) external onlySentry {
        require(
            isNameAvailable(account, nodeName),
            "CREATE NODE: Name not available"
        );
        _nodesOfUser[account].push(
            NodeEntity({
                name: nodeName,
                creationTime: block.timestamp,
                lastClaimTime: block.timestamp,
                rewardAvailable: 0
            })
        );
        nodeOwners.set(account, _nodesOfUser[account].length);
        totalNodesCreated++;
    }

    function createNodes(address[] calldata accounts, string[] calldata nodeNames) external onlySentry {
        require(accounts.length == nodeNames.length, "INCONSISTENT_LENGTH");
        for(uint256 i = 0; i < accounts.length; i++) {
             require(
                isNameAvailable(accounts[i], nodeNames[i]),
                "CREATE NODE: Name not available"
            );
            _nodesOfUser[accounts[i]].push(
                NodeEntity({
                    name: nodeNames[i],
                    creationTime: block.timestamp,
                    lastClaimTime: block.timestamp,
                    rewardAvailable: 0
                })
            );
            nodeOwners.set(accounts[i], _nodesOfUser[accounts[i]].length);
            totalNodesCreated++;
        }
    }

    function createNodesForAccount(address account, string[] calldata nodeNames) external onlySentry {
        for(uint256 i = 0; i < nodeNames.length; i++) {
            require(
                isNameAvailable(account, nodeNames[i]),
                "CREATE NODE: Name not available"
            );
            _nodesOfUser[account].push(
                NodeEntity({
                    name: nodeNames[i],
                    creationTime: block.timestamp,
                    lastClaimTime: block.timestamp,
                    rewardAvailable: 0
                })
            );
        }
        nodeOwners.set(account, _nodesOfUser[account].length);
        totalNodesCreated++;
    }

    function _renameNode(address account, string memory oldName, string memory newName) external onlySentry {
      uint256 index = _getNodeByName(account, oldName);
      require(index != uint(int(-1)), "Node doesn't exist");

      NodeEntity storage node = _nodesOfUser[account][index];
      node.name = newName;
    }

    function addRewardToNode(address account, string memory name, uint256 amount) external onlySentry {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        uint256 index = _getNodeByName(account, name);
        require(index != uint(int(-1)), "Node doesn't exist");

        NodeEntity storage node = _nodesOfUser[account][index];
        node.rewardAvailable += amount;
    }

    function isNameAvailable(address account, string memory nodeName)
    private
    view
    returns (bool)
    {
        NodeEntity[] memory nodes = _nodesOfUser[account];
        for (uint256 i = 0; i < nodes.length; i++) {
            if (keccak256(bytes(nodes[i].name)) == keccak256(bytes(nodeName))) {
                return false;
            }
        }
        return true;
    }

    function _burn(uint256 index) internal {
        require(index < nodeOwners.size());
        nodeOwners.remove(nodeOwners.getKeyAtIndex(index));
    }

    function _getNodeByName(address account, string memory name) private view returns (uint) {
        NodeEntity[] storage nodes = _nodesOfUser[account];

        for (uint256 i = 0; i < nodes.length; i++) {
            if (keccak256(bytes(nodes[i].name)) == keccak256(bytes(name))) {
                return i;
            }
        }

        return uint(int(-1));
    }

    function _getNodeWithCreationTime(NodeEntity[] storage nodes, uint256 _creationTime) private view returns (NodeEntity storage) {
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i].creationTime == _creationTime) {
                return nodes[i];
            }
        }

        revert();
    }

    function isNodeClaimable(NodeEntity memory node) private view returns (bool) {
        return node.lastClaimTime + claimTime <= block.timestamp;
    }

    function _availableClaimableAmount(uint256 nodeLastClaimTime) private view returns (uint256 availableRewards) {
        return ((block.timestamp - nodeLastClaimTime) / claimTime) * rewardPerSecond;
    }   
    
    function _cashoutNodeReward(address account, uint256 _creationTime)
    external onlySentry
    returns (uint256)
    {
        require(_creationTime > 0, "NODE: CREATIME must be higher than zero");
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(
            numberOfNodes > 0,
            "CASHOUT ERROR: You don't have nodes to cash-out"
        );
        NodeEntity storage node = _getNodeWithCreationTime(nodes, _creationTime);
        require(isNodeClaimable(node), "TOO_EARLY_TO_CLAIM");
        uint256 rewardNode = _availableClaimableAmount(node.lastClaimTime) + node.rewardAvailable;

        node.lastClaimTime = block.timestamp;

        node.rewardAvailable = 0;
        return rewardNode;
    }

    function _cashoutAllNodesReward(address account)
    external onlySentry
    returns (uint256)
    {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, "NODE: Count must be higher than zero");
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        for (uint256 i = 0; i < nodesCount; i++) {
            _node = nodes[i];
            rewardsTotal += _availableClaimableAmount(_node.lastClaimTime) + _node.rewardAvailable;
            _node.rewardAvailable = 0;
            _node.lastClaimTime = block.timestamp;
        }
        return rewardsTotal;
    }

    function claimable(NodeEntity memory node) private view returns (bool) {
        return node.lastClaimTime + claimTime <= block.timestamp;
    }

    function _getRewardAmountOf(address account)
    external
    view
    returns (uint256)
    {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        uint256 nodesCount;
        uint256 rewardCount = 0;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

        for (uint256 i = 0; i < nodesCount; i++) {
            NodeEntity memory node = nodes[i];
            rewardCount +=_availableClaimableAmount(node.lastClaimTime) + node.rewardAvailable;
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 _creationTime)
    external
    view
    returns (uint256)
    {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");

        require(_creationTime > 0, "NODE: CREATIME must be higher than zero");
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(
            numberOfNodes > 0,
            "CASHOUT ERROR: You don't have nodes to cash-out"
        );
        NodeEntity storage node = _getNodeWithCreationTime(nodes, _creationTime);
        return _availableClaimableAmount(node.lastClaimTime) + node.rewardAvailable;
    }


    function _getNodeRewardAmountOf(address account, uint256 creationTime)
    external
    view
    returns (uint256)
    {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        return _getNodeWithCreationTime(nodes, creationTime).rewardAvailable;
    }

    function _getNodesNames(address account)
    external
    view
    returns (string memory)
    {
        require(isNodeOwner(account), "GET NAMES: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory names = nodes[0].name;
        string memory separator = "#";
        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            names = string(abi.encodePacked(names, separator, _node.name));
        }
        return names;
    }

    function _getNodesCreationTime(address account)
    external
    view
    returns (string memory)
    {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _creationTimes = uint2str(nodes[0].creationTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _creationTimes = string(
                abi.encodePacked(
                    _creationTimes,
                    separator,
                    uint2str(_node.creationTime)
                )
            );
        }
        return _creationTimes;
    }

    function _getNodesRewardAvailable(address account)
    external
    view
    returns (string memory)
    {
        require(isNodeOwner(account), "GET REWARD: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;

        string memory _rewardsAvailable = uint2str(_availableClaimableAmount(nodes[0].lastClaimTime) + nodes[0].rewardAvailable);

        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _rewardsAvailable = string(
                abi.encodePacked(
                    _rewardsAvailable,
                    separator,
                    uint2str(_availableClaimableAmount(_node.lastClaimTime) + _node.rewardAvailable)
                )
            );
        }
        return _rewardsAvailable;
    }

    function _getNodesLastClaimTime(address account)
    external
    view
    returns (string memory)
    {
        require(isNodeOwner(account), "LAST CLAIME TIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _lastClaimTimes = uint2str(nodes[0].lastClaimTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _lastClaimTimes = string(
                abi.encodePacked(
                    _lastClaimTimes,
                    separator,
                    uint2str(_node.lastClaimTime)
                )
            );
        }
        return _lastClaimTimes;
    }

    function uint2str(uint256 _i)
    internal
    pure
    returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _changeNodePrice(uint256 newNodePrice) external onlySentry {
        nodePrice = newNodePrice;
    }

    function _changeRewardPerNode(uint256 newPrice) external onlySentry {
        rewardPerNode = newPrice;
    }

    function _changeClaimTime(uint256 newTime) external onlySentry {
        claimTime = newTime;
    }

    function _changeAutoDistri(bool newMode) external onlySentry {
        autoDistri = newMode;
    }

    function _changeGasDistri(uint256 newGasDistri) external onlySentry {
        gasForDistribution = newGasDistri;
    }

    function _getNodeNumberOf(address account) public view returns (uint256) {
        return nodeOwners.get(account);
    }

    function isNodeOwner(address account) private view returns (bool) {
        return nodeOwners.get(account) > 0;
    }

    function _isNodeOwner(address account) external view returns (bool) {
        return isNodeOwner(account);
    }

    function _transferNode(address from, address to, string memory nodeName) 
                                                    external onlySentry returns (bool) {

        require(!isNameAvailable(from, nodeName), "");

        require(isNameAvailable(to, nodeName), "");

        uint index = _getNodeByName(from, nodeName);

        require(index != uint(int(-1)), "Node does not exist");

        NodeEntity[] storage nodes = _nodesOfUser[from];
        uint last = nodes.length - 1;

        _nodesOfUser[to].push(nodes[index]);

        nodes[index] = nodes[last];
        nodes.pop();

        nodeOwners.set(from, _nodesOfUser[from].length);
        nodeOwners.set(to, _nodesOfUser[to].length);

        if (last == 1)
            nodeOwners.remove(from);

        return true;
    }
}