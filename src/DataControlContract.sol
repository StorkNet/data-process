// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title StorkNet's OnChain Data Control Contract
/// @author Shankar "theblushirtdude" Subramanian
/// @notice
/// @dev This contract is used to manage the on-chain data of StorkContracts.
contract DataControlContract {
    /// @dev Only validated users can access the function
    modifier OnlyStorkNodes() {
        require(storkNodes[msg.sender].isActive == true, "Not a validator");
        _;
    }

    /// @dev Only the multi sig wallet can access these functions that update batches so that we lower gas fees
    modifier onlyMultiSigWallet() {
        require(msg.sender == multiSigVerifierContract, "Not multi sig wallet");
        _;
    }

    /// @dev Stores data about the StorkNodes
    /// @custom: amount staked,
    /// @custom: the duration till when the StorkNode is active, after which it can get back it's stake
    /// @custom: the number of transactions handled by the StorkNode
    /// @custom: whether or not this StorkNode is active to handle data requests

    struct StorkNode {
        uint256 stakeValue;
        uint256 stakeEndTime;
        uint256 txCount;
        bool isActive;
    }

    /// @dev Stores data about the StorkContracts
    /// @custom: number of transactions handled for the StorkContract,
    /// @custom: whether or not this StorkContract is active for data requests
    struct StorkContract {
        uint256 txLeft;
        bool isActive;
    }

    /// @notice The minimum stake required to be a StorkNode or StorkContract
    /// @dev The stake is used to validate Validators and also to compensate/pay Validators for transactions they handle
    uint256 public minStake;

    /// @notice The cost per transaction to be paid by the StorkContract
    /// @dev Reduces the amount staked by the StorkContract
    uint256 public costPerTx;

    /// @notice The cost per transaction to be paid by the StorkContract
    /// @dev Reduces the amount staked by the StorkContract
    address public immutable multiSigVerifierContract;

    /// @notice Stake duration
    uint256 public constant stakeTime = 4 weeks;

    /// @notice Has the data of all StorkNodes
    /// @dev Maps an address to a StorkNode struct containing the data about the address
    mapping(address => StorkNode) public storkNodes;

    /// @notice Has the data of all StorkContracts
    /// @dev Maps an address to a StorkContract struct containing the data about the address
    mapping(address => StorkContract) public storkContracts;

    /// @notice Initializes the contract
    /// @dev Sets up the contract with minimum stake, cost per tx, and the address of the multi sig verifier
    /// @param _minStake the minumum stake required to be a StorkNode or StorkContract
    /// @param _costPerTx the cost per transaction to be paid by the StorkContract
    /// @param _multiSigVerifierContract the address of the multi sig verifier

    constructor(
        uint256 _minStake,
        uint256 _costPerTx,
        address _multiSigVerifierContract
    ) {
        minStake = _minStake;
        costPerTx = _costPerTx;
        multiSigVerifierContract = _multiSigVerifierContract;
    }

    /// @notice Allows an address to add themselves as a StorkNode if they send a transaction greater than the minStake
    /// @dev Checks if the tx sender sent enough funds to be a StorkNode and if so, adds them to the storkNodes mapping
    function addStorkNode() external payable {
        require(
            msg.value > minStake,
            "Deposit must be greater than the minStake"
        );
        require(msg.sender != address(0), "Can't be null address");

        storkNodes[msg.sender] = StorkNode({
            stakeValue: msg.value,
            stakeEndTime: block.timestamp + stakeTime, //gets the end time of the stake
            txCount: 0,
            isActive: true
        });

        emit NodeStaked(msg.sender, storkNodes[msg.sender].stakeEndTime);
    }

    /// @notice Increases the fund of a StorkNode by the amount sent
    /// @dev Increases the fund of a StorkNode by the amount sent and also the duration of the stake for the StorkNode
    /// @param _days increases the duration of the stake by the number of days sent
    function fundStorkNodeStake(uint256 _days) external payable {
        require(msg.value > 0, "Stake must be greater than 0");

        storkNodes[msg.sender].stakeValue += msg.value;

        // extends duration of the stake by the number of days sent by converting the days to seconds
        storkNodes[msg.sender].stakeEndTime += block.timestamp + _days * 1 days;

        emit NodeStakeExtended(msg.sender, storkNodes[msg.sender].stakeEndTime);
    }

    /// @notice Batch update of the StorkNode data based on the number of transactions they handled
    /// @dev Updates the count of transactions handled by the StorkNode since the last Batch update
    /// @param _txNodeAddrs an array of all the addresses of the StorkNodes involved in the batch Tx
    /// @param _txNodeCounts an array of the count of Txs handled by the StorkNodes involved in the batch Tx
    function storkNodeTxBatcher(
        address[] calldata _txNodeAddrs,
        uint256[] calldata _txNodeCounts
    ) external onlyMultiSigWallet {
        // makes sure the Address array and the Address Tx count arrays are the same length
        require(
            _txNodeAddrs.length == _txNodeCounts.length,
            "Length of arrays must be equal"
        );

        for (uint256 i = 0; i < _txNodeAddrs.length; ++i) {
            storkNodes[_txNodeAddrs[i]].txCount += _txNodeCounts[i];
        }
    }

    // -----------------------------------------------------------------------------------------------------------------

    /// @notice Allows a Contract to add themselves as a StorkContract if they send a transaction greater than minStake
    /// @dev using the Funds received compute the max number of transactions that can be trasacted by the Contract
    function addStorkContract() external payable {
        require(msg.value > minStake, "Funds must be greater than minStake");

        // Computes the max number of transactions that can be handled by the Contract
        storkContracts[msg.sender] = StorkContract({
            txLeft: msg.value / costPerTx,
            isActive: true
        });

        emit ContractCreated(msg.sender, msg.value / costPerTx);
    }

    /// @notice Any user can further fund a StorkContract
    /// @dev Increase the number of transactions of the StorkContract based on the funding
    /// @param _storkContractAddr address of the stork contract that is being funded
    function fundStorkContract(address _storkContractAddr) external payable {
        require(msg.value > 0, "Funds must be greater than 0");
        require(msg.sender != address(0), "Can't be null address");

        storkContracts[_storkContractAddr].txLeft += msg.value / costPerTx;
        
        emit ContractFunded(
            _storkContractAddr,
            msg.value / costPerTx,
            storkContracts[_storkContractAddr].txLeft
        );
    }

    /// @notice Batch update of the StorkContracts based on the number of transactions they were involved with
    /// @dev Updates the number of transactions that a StorkContract can handle after this batch update
    /// @param txId The id of the batch Tx
    /// @param _txContractAddrs an array of the StorkContracts involved in the batch Tx
    /// @param _txContractCounts an array of the count of Txs handled for the StorkContracts involved in the batch Tx
    function contractTxBatcher(
        uint256 txId,
        address[] calldata _txContractAddrs,
        uint256[] calldata _txContractCounts
    ) external onlyMultiSigWallet {
        
        /// @notice Checks if the batch went smoothly without any contracts involved in errors
        /// @dev If a StorkContract has run out of Txs, emit a error event stating the same
        bool txBatchingClean = true;
        for (uint256 i = 0; i < _txContractAddrs.length; ++i) {
            // checks if the StorkContract has run out of Txs
            if (
                storkContracts[_txContractAddrs[i]].txLeft >
                _txContractCounts[i]
            ) {
                emit ContractOutOfFund(txId, _txContractAddrs[i]);
                txBatchingClean = false;
            }

            // updates the number of transactions left for the StorkContract 
            storkContracts[_txContractAddrs[i]].txLeft -= _txContractCounts[i];
        }

        emit BatchUpdate(txId, txBatchingClean);
    }

    // -----------------------------------------------------------------------------------------------------------------

    function changeTxCost(uint256 newCostPerTx) external onlyMultiSigWallet {
        costPerTx = newCostPerTx;
        emit NewCostPerTx(newCostPerTx);
    }

    function changeMinStake(uint256 newMinStake) external onlyMultiSigWallet {
        minStake = newMinStake;
        emit NewMinStake(newMinStake);
    }

    fallback() external payable {}

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    event Deposit(address indexed _addr, uint256 _value);
    event NewCostPerTx(uint256 indexed newCostPerTx);
    event NewMinStake(uint256 indexed newMinStake);
    event NodeStaked(address indexed newNode, uint256 time);
    event NodeStakeExtended(address indexed newNode, uint256 newTime);
    event ContractCreated(
        address indexed newContract,
        uint256 indexed fundValue
    );
    event ContractFunded(
        address indexed oldContract,
        uint256 indexed fundValue,
        uint256 newFundTotal
    );
    event BatchUpdate(uint256 indexed txId, bool indexed updateStatus);
    event ContractOutOfFund(
        uint256 indexed txId,
        address indexed contractOnLowFund
    );
}
