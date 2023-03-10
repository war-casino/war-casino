
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface WarToken is IERC20 {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
    
}


contract WARBETS is Ownable, ReentrancyGuard {

    uint constant public CONTRACT_CUT = 2; // 2% of bet goes to contract    

    // Define roles for the pool contract
    enum Roles {
        PoolCreator,
        Mediator,
        Winner
    }

    struct Pool {
        address[] users;
        mapping(address => uint) userBalances;
        uint balance;
        address mediator;
        uint timeLock;
        bool timeLocked;        
        uint numUsers;
        uint mediatorCut;
        address poolId;
        mapping(address => Roles) userRoles; // New field to track user roles in this pool
    }

    address[] public poolAddresses;
    mapping(address => uint) public userBalances;
    uint public poolBalance;    
    address public mediator;
    uint public timeLock;
    bool public timeLocked;    

    event BetPlaced(address indexed user, uint amount);
    event PoolLocked(uint time);

    // Mapping of user addresses to their roles in the pool contract
    mapping(address => Roles) public userRoles;

    // Event to notify when a user role has been changed
    event UserRoleChanged(address indexed user, Roles role);


    modifier onlyFirstUser() {
        require(msg.sender == firstUser, "Only first user can call this function");
        _;
    }

    modifier onlyMediator() {
        require(msg.sender == mediator, "Only mediator can call this function");
        _;
    }

    modifier onlyAllowedAddresses() {
        require(allowedAddresses[msg.sender], "Only allowed addresses can call this function");
        _;
    }

    constructor(uint _poolSize, address[] memory _allowedAddresses, uint _timeLock, uint _mediatorFee) {
        firstUser = msg.sender;
        poolSize = _poolSize;
        timeLock = _timeLock;
        mediatorFee = _mediatorFee;
        timeLocked = false;

        for (uint i = 0; i < _allowedAddresses.length; i++) {
            allowedAddresses[_allowedAddresses[i]] = true;
        }
    }

    function createReservedPool(
        address[] memory _users, 
        uint _timeLock, 
        address _mediator,
        uint _mediatorCut,
        string memory _eventMetadata,
        bool _timeLockEnabled,
        uint _minimumBetAmount,
        string memory _mediatorDetails
    ) public payable {
        require(msg.value > 0, "Pool balance must be greater than 0");
        require(_users.length > 1, "There must be at least 2 users in the pool");    

        Pool storage pool;
        poolCount++;

        for (uint i = 0; i < _users.length; i++) {
            pool.users.push(_users[i]);
        }

        pool.balance = msg.value;
        pool.mediator = _mediator;
        pool.timeLock = _timeLock;
        pool.mediatorCut = _mediatorCut;    

        pool.eventMetadata = _eventMetadata;
        pool.timeLockEnabled = _timeLockEnabled;
        pool.minimumBetAmount = _minimumBetAmount;
        pool.mediatorDetails = _mediatorDetails;
    }

    function joinReservedPool(uint _poolId) public payable {
        Pool storage pool = pools[_poolId];
        require(msg.value == pool.minimumBetAmount, "Bet amount must be equal to the minimum bet amount");

        pool.users.push(msg.sender);
        pool.balance += msg.value;
    }


    function createPool(
    uint _timeLock,
    address _mediator,
    uint _mediatorCut,
    string memory _metadata,
    bool _timeLockEnabled,
    uint _minimumBetAmount,
    string memory _mediatorDetails,
    uint _maxUsers,
    string memory _poolName
    ) public payable {
        require(msg.value > _minimumBetAmount, "Pool balance must be greater than 0");
        require(_maxUsers > 1, "There must be at least 2 authorized users in the pool");    

        Pool storage pool;
        poolCount++;

        pool.userRoles[msg.sender] = Roles.PoolCreator;

        pool.users.push(msg.sender);
        pool.maxUsers = _maxUsers;

        pool.balance = msg.value;
        pool.mediator = _mediator;
        pool.timeLock = _timeLock;
        pool.mediatorCut = _mediatorCut;
        pool.contractCut = CONTRACT_CUT;

        pool.metadata = _metadata;
        pool.timeLockEnabled = _timeLockEnabled;
        pool.minimumBetAmount = _minimumBetAmount;
        pool.mediatorDetails = _mediatorDetails;

        // Concatenate the pool ID using the pool name, pool creator address, mediator address, and metadata
        bytes32 poolId = keccak256(abi.encodePacked(_poolName, msg.sender, _mediator, _metadata));
        pool.poolId = poolId;

        // Assign the PoolCreator role to the user who creates the pool
        pool.userRoles[_mediator] = Roles.PoolMediator;
    }



    function joinPool(uint _poolId) public payable {
        Pool storage pool = pools[_poolId];
        require(pool.users.length < pool.maxUsers, "Pool has reached maximum number of authorized users");
        require(msg.value == pool.minimumBetAmount, "Bet amount must be equal to the minimum bet amount");

        pool.users.push(msg.sender);
        pool.balance += msg.value;
    }

    function joinPool() external payable onlyAllowedAddresses {
        require(numUsers < poolSize, "Pool is already full");
        require(userBalances[msg.sender] == 0, "User has already joined pool");
        require(msg.value > 0, "User must send non-zero amount");

        userBalances[msg.sender] = msg.value;
        poolBalance += msg.value;
        poolAddresses[numUsers] = msg.sender;
        numUsers++;

        emit BetPlaced(msg.sender, msg.value);
    }

    function lockPool(address _mediator) external onlyFirstUser {
        require(numUsers >= 2, "Pool must have at least 2 users to lock");
        require(!timeLocked, "Pool is already time-locked");

        timeLocked = true;
        mediator = _mediator;
        emit PoolLocked(block.timestamp + timeLock);
    }

    function claimWin() external onlyMediator {
        require(timeLocked && block.timestamp >= (poolBalance * 2) + timeLock, "Pool is not ready to be claimed");
        uint winningCondition = uint(keccak256(abi.encodePacked(block.timestamp, poolBalance))) % numUsers;
        address winner = poolAddresses[winningCondition];

        uint mediatorCut = mediatorFee * poolBalance / 100;
        uint contractCut = 5 * poolBalance / 100;
        uint userCut = (poolBalance - mediatorCut - contractCut) / numUsers;

        payable(mediator).transfer(mediatorCut);
        payable(address(this)).transfer(contractCut);

        for (uint i = 0; i < numUsers; i++) {
            if (poolAddresses[i] != winner) {
                payable(poolAddresses[i]).transfer(userCut);
            } else {
                payable(winner).transfer(poolBalance - mediatorCut - contractCut - (userCut * (numUsers - 1)));
            }
            userBalances[poolAddresses[i]] = 0; // Clear user balances
        }

        poolBalance = 0;
        numUsers = 0;
        timeLocked = false;
    }

    function withdraw() external {
        require(userBalances[msg.sender] > 
        uint userBalance = userBalances[msg.sender];
        userBalances[msg.sender] = 0;
        payable(msg.sender).transfer(userBalance);
    }

    function getPoolAddresses() external view returns (address[] memory) {
        address[] memory addresses = new address[](numUsers);
        for (uint i = 0; i < numUsers; i++) {
            addresses[i] = poolAddresses[i];
        }
        return addresses;
    }
}