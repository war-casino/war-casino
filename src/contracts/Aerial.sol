// test: 0xcC9De99b32750a0550380cb8495588ca2f48d533
// previous: 0x20c375C04e22E600A2BD4Bb9c4499483942Fa7C7
// latest: 0x20F173DF4580e900E39b0Dc442e0c54e7E133066
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface WarToken is IERC20 {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract AERIAL is Ownable, ReentrancyGuard, RrpRequesterV0, AccessControl {
    using SafeMath for uint256;

    uint256 public totalPlays;

    /******************/

    mapping(address => bytes32) public userId;
    mapping(bytes32 => address) public requestUser;
    mapping(bytes32 => uint256) public randomNumber;
    mapping(address => uint256) public betsize;
    mapping(address => uint8[2]) public coord;

    mapping(address => uint256) public userTotalBet;
    mapping(address => uint256) public userTotalWon;
    mapping(address => uint256) public userTotalLost;

    uint256 public devFees;
    uint256 public warFees;
    // mapping(address => uint256) public userHighscore;

    mapping(address => bool) public inGame;
    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;

    uint256 public poolIndex;

    uint256 public highscore;
    address public highscoreHolder;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;
    address internal devAddress;

    uint256 public gridSize;
    uint256 public qfee = 100000000000000;

    uint256 public totalWins;
    uint256 public totalWon;

    uint256 totalLosses;
    uint256 totalLost;

    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 config,
        uint256 x,
        uint256 y,
        bool won,
        uint256 Amount
    );    

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    bool gameActive;

    address botContract;

    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant WAR_ROLE = keccak256("WAR_ROLE");

    constructor(address _airnodeRrp, address _warTokenAddress)
        RrpRequesterV0(_airnodeRrp)
    {
        warToken = WarToken(_warTokenAddress);
    }

    function GetUserTokenBalance() public view returns (uint256) {
        return warToken.balanceOf(msg.sender); // balancdOf function is already declared in ERC20 token function
    }

    function GetAllowance() public view returns (uint256) {
        return warToken.allowance(msg.sender, address(this));
    }    

    function GetContractTokenBalance() public view onlyOwner returns (uint256) {
        return warToken.balanceOf(address(this));
    }

    modifier onlyOwnerBot() {
        require(
            (msg.sender == owner()) || (msg.sender == botContract),
            "Only Owner or Bot"
        );
        _;
    }

    function setBot(address _botContract) public onlyOwner {
        botContract = _botContract;
    }

    function removeDev(address _dev) public onlyOwner {
        devAddress = _dev;
        _setupRole(WITHDRAWER_ROLE, _dev);
    }

    function setDev(address _dev) public onlyOwner {
        devAddress = _dev;
        _setupRole(WITHDRAWER_ROLE, _dev);
    }

    function setQfee(uint256 _qfee) public onlyOwner {
        require(_qfee <= 200000000000000, "Dont set fee too high");
        require(_qfee >= 50000000000000, "Dont set fee too low");
        qfee = _qfee;
    }

    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256,
        address _sponsorWallet
    ) external onlyOwner {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        sponsorWallet = _sponsorWallet;
    }

    function makeRequestUint256(address userAddress) internal {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        userId[userAddress] = requestId;
        requestUser[requestId] = userAddress;
        emit RequestedUint256(requestId);
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param data ABI-encoded response
    function fulfillUint256(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(requestUser[requestId] != address(0), "Request ID not known");
        uint256 qrngUint256 = abi.decode(data, (uint256));
        // Do what you want with `qrngUint256` here...
        randomNumber[requestId] = qrngUint256;

        emit ReceivedUint256(requestUser[requestId], requestId, qrngUint256);
    }

    function setGrid(uint8 n) public onlyOwner {
        gridSize = n;
    }

    function Fire(
        uint256 _amount,
        uint8 x,
        uint8 y
    ) public payable nonReentrant {
        require(gridSize > 3, "GridSize needs to be greater then 3");
        require(_amount > 0, "Send at least 1 War token");
        require((x < gridSize) && (x >= 0), "x value is out of bounds");
        require(((y < gridSize) && (y >= 0)), "y value is out of bounds");
        require(
            !inGame[msg.sender],
            "Check the results of your last game first"
        );
        require(devAddress != address(0),"owner must set dev address");
        require(_amount <= GetAllowance(),"owner must set dev address");

        uint256 tempDevFee = SafeMath.div(_amount, 100);

        devFees += SafeMath.div(tempDevFee,2);
        warFees += SafeMath.div(tempDevFee,2);
        uint256 playerBet = _amount - tempDevFee;

        // Transfer 2% to front end dev 2% to war chest
        require(warToken.transferFrom(msg.sender, address(this), tempDevFee), "Token transfer failed");

        
        // pay randomness sponser wallet to cover gas
        payable(sponsorWallet).transfer(qfee);

        // burn remaining tokens
        warToken.gameBurn(msg.sender, playerBet);
        makeRequestUint256(msg.sender);
        coord[msg.sender] = [x, y];
        inGame[msg.sender] = true;
        betsize[msg.sender] = playerBet;
        emit bet(msg.sender, _amount);
    }

    function Reveal() public nonReentrant {
        require(gridSize > 3, "gridMatrix has no values");
        bytes32 requestId = userId[msg.sender];
        require(requestId != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[requestId] != uint256(0)),
            "Random number not ready, try again."
        );
        require(inGame[msg.sender], "Launch a nuke to start bro.");        

        uint256 secretnum = (randomNumber[requestId] %
            (((gridSize - 1) * (gridSize - 1)) - 1));
        uint256 userBet = betsize[msg.sender];
        userTotalBet[msg.sender] += userBet;

        uint256 winAmount = Math.mulDiv(userBet, computePayout(gridSize), 4) +
            userBet;

        uint8[2] memory xy = coord[msg.sender];
        uint8 x = xy[0];
        uint8 y = xy[1];
        bool check = checkMatch(secretnum, x, y);

        if (check) {
            warToken.gameMint(msg.sender, winAmount);
            ++totalWins;
            totalWon += winAmount;
            userTotalWon[msg.sender] += (winAmount-userBet);
            emit win(msg.sender, secretnum, x, y, true, winAmount);
        } else {
            ++totalLosses;
            totalLost += userBet;
            userTotalLost[msg.sender] += userBet;
            emit win(msg.sender, secretnum, x, y, false, userBet);
        }
        ++totalPlays;

        delete inGame[msg.sender];
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete coord[msg.sender];        
    }

    // inactive but might add for future implementations
    function ChangeStatus(bool _newStatus) public onlyOwnerBot {
        gameActive = _newStatus;
    }

    function leaveGame() public {
        if (!inGame[msg.sender]) 
        {
            revert("Not in a game");
        }                
        bytes32 requestId = userId[msg.sender];
        if(randomNumber[requestId] == uint256(0))
        {
            warToken.gameMint(msg.sender,betsize[msg.sender]);
        }
        delete inGame[msg.sender];
        delete requestUser[requestId];
        delete randomNumber[requestId];
        delete userId[msg.sender];
        delete betsize[msg.sender];        
        delete coord[msg.sender];
    }

    function checkMatch(
        uint256 k,
        uint8 x,
        uint8 y
    ) public view returns (bool) {
        uint8[8] memory solution = generateSolutions(gridSize, k);
        uint256 end = solution.length;
        for (uint256 i = 0; i < end; i += 2) {
            if (solution[i] == x && solution[i + 1] == y) {
                return true;
            }
        }
        return false;
    }

    function generateSolutions(uint256 n, uint256 k)
        public
        pure
        returns (uint8[8] memory)
    {
        require(k < ((n - 1) * (n - 1)), "K is too large");
        require(k >= 0, "K is less than 0");
        uint8 i = uint8(k / (n - 1));
        uint8 j = uint8(k % (n - 1));
        uint8[8] memory temp = [i, j, i + 1, j, i, j + 1, i + 1, j + 1];
        return temp;
    }

    function computePayout(uint256 n) public pure returns (uint256) {
        uint256 safeOdds = SafeMath.mul(SafeMath.sub(n, 1), SafeMath.sub(n, 1));
        return safeOdds;
    }

    function devWithdrawWar(address recipient) public {
        require(
            hasRole(WITHDRAWER_ROLE, msg.sender),
            "MyContract: must have withdrawer role to withdraw"
        );
        warToken.transfer(recipient, devFees);
        devFees = 0;
    }

    function warWithdrawWar(address _recipient) onlyOwner public {
        require(
            hasRole(WAR_ROLE, msg.sender),
            "MyContract: must have withdrawer role to withdraw"
        );
        warToken.transfer(_recipient, warFees);
        warFees = 0;
    }

    function withdraw(address _recipient) public payable onlyOwner {
        payable(_recipient).transfer(address(this).balance);
    }
}
