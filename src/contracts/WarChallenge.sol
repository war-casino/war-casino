// 0xe9BC99EFa4aDedBb16d94c3dB63674bf788f51e1
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface WarToken {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract WARCHALLENGE is Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

    uint256 public totalPlays;
    /******************/
        

    mapping(address => bool) public inGame;

    mapping(address => bytes32) public userReservedId;
    mapping(bytes32 => address) public requestReservedUser;
    mapping(bytes32 => uint256) public randomReservedNumber;
    mapping(address => uint256) public betReservedSize;

    mapping(address => bool) public userReservedPool;
    mapping(address => address) public userReservedToOpponent;
    mapping(address => address) public opponentReservedToUser;
    mapping(address => uint256) public cardReserved;

    mapping(address => uint256) public drawTime;
    
    address public highscore;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;

    uint256 public qfee = 50000000000000;

    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 myCard,
        uint256 theirCard,
        bool won,
        uint256 amount
    );

    event EnteredPool(address indexed player);
    event EnteredReservedPool(address indexed player, address opponent);

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    constructor(address _airnodeRrp, address _warTokenAddress)
        RrpRequesterV0(_airnodeRrp)
    {
        warToken = WarToken(_warTokenAddress);
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

    function fulfillUint256(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(requestReservedUser[requestId] != address(0), "Request ID not known");
        uint256 qrngUint256 = abi.decode(data, (uint256));
        // Do what you want with `qrngUint256` here...
        randomReservedNumber[requestId] = qrngUint256;

        emit ReceivedUint256(requestReservedUser[requestId], requestId, qrngUint256);
    }

    function makeReservedRequestUint256(address userAddress) internal {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        userReservedId[userAddress] = requestId;
        requestReservedUser[requestId] = userAddress;
        emit RequestedUint256(requestId);
    }

    function enterChallenge(address opponent, uint256 _amount) public {
        require(
            !inGame[msg.sender],
            "Can only open one challenge at a time"
        );
        require(_amount > 0, "Must include a bet amount");
        require(
            userReservedToOpponent[msg.sender] == address(0),
            "Can only open one challenge at a time"
        );
        if(opponentReservedToUser[msg.sender] != address(0))
        {            
            userReservedToOpponent[msg.sender] = opponent;
        opponentReservedToUser[opponent] = msg.sender;    
        }
        address payable sendAddress = payable(sponsorWallet);
        sendAddress.transfer(qfee);
        userReservedPool[msg.sender] = true;
        betReservedSize[msg.sender] = _amount;
        userReservedToOpponent[msg.sender] = opponent;
        opponentReservedToUser[opponent] = msg.sender;

        makeReservedRequestUint256(msg.sender);
        warToken.gameBurn(msg.sender, _amount);

        emit EnteredReservedPool(msg.sender, opponent);
        emit bet(msg.sender, _amount);
    }

    function leaveReserved() public {
        require(
            userReservedPool[msg.sender],
            "You Must have an open challenge"
        );
        bytes32 requestId = userReservedId[msg.sender];
        require(
            randomReservedNumber[requestId] != 0,
            "Must wait for random number to generate to clean out variables"
        );
        address opponent = userReservedToOpponent[msg.sender];
        require(
            !userReservedPool[opponent],
            "Cannot leave the pool after your opponent has entered"
        );

        warToken.gameMint(msg.sender, betReservedSize[msg.sender]);

        delete userReservedToOpponent[msg.sender];
        delete opponentReservedToUser[opponent];
        delete userReservedPool[msg.sender];
        delete userReservedId[msg.sender];
        delete randomReservedNumber[requestId];
        delete betReservedSize[msg.sender];
        delete requestReservedUser[requestId];
        delete inGame[msg.sender];
    }

    function drawReserved() public nonReentrant {
        require(
            userReservedId[msg.sender] != bytes32(0),
            "User has no unrevealed numbers."
        );
        require(
            (randomReservedNumber[userReservedId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            cardReserved[msg.sender] == uint256(0),
            "Card has been assigned, reveal to view results"
        );
        address opponent = userReservedToOpponent[msg.sender];
        require(
            userReservedToOpponent[opponent] != address(0),
            "Selected Player needs to enter the Reserved pool"
        );

        bytes32 requestId = userReservedId[msg.sender];
        uint256 secretnum = (randomReservedNumber[requestId] % 12) + 1;
        drawTime[msg.sender] = block.timestamp;
        cardReserved[msg.sender] = secretnum;

        delete randomReservedNumber[requestId];        
        delete userReservedPool[msg.sender];
        delete requestReservedUser[requestId];
        delete userReservedPool[msg.sender];
        if(cardReserved[opponent] != 0)
        {
            delete userReservedToOpponent[msg.sender];
            delete opponentReservedToUser[opponent];
            delete userReservedToOpponent[opponent];
            delete opponentReservedToUser[msg.sender];  
            delete userReservedId[msg.sender];
        }
    }

    function RevealReserved() public nonReentrant {
        require(
            cardReserved[msg.sender] != 0,
            "Card has not been assigned, draw your card"
        );
        address opponent = userReservedToOpponent[msg.sender];
        require(cardReserved[opponent] != 0, "Opponent has not drawn a card");
        uint256 myCard = cardReserved[msg.sender];
        uint256 theirCard = cardReserved[opponent];

        uint256 userBet = betReservedSize[msg.sender];
        uint256 opponentBet = betReservedSize[opponent];
        uint256 payoutWin;
        uint256 delta;
        if (userBet >= opponentBet) {
            payoutWin = userBet + opponentBet;
            delta = userBet - opponentBet;
        } else {
            payoutWin = userBet + userBet;
        }
        if (myCard > theirCard) {
            emit win(msg.sender, myCard, theirCard, true, payoutWin);
            warToken.gameMint(msg.sender, payoutWin);
            if (delta > 0) {
                warToken.gameMint(opponent, delta);
            }
        } else if (myCard == theirCard) {
            emit win(msg.sender, myCard, theirCard, false, userBet);
            warToken.gameMint(msg.sender, userBet);
            warToken.gameMint(opponent, opponentBet);
        } else {
            emit win(msg.sender, myCard, theirCard, false, delta);
            uint256 payoutOpponent = (opponentBet + userBet) - delta;
            warToken.gameMint(msg.sender, delta);
            warToken.gameMint(opponent, payoutOpponent);
        }
        ++totalPlays;
        delete userReservedToOpponent[msg.sender];
        delete opponentReservedToUser[msg.sender];
        delete userReservedToOpponent[opponent];
        delete opponentReservedToUser[opponent];
        delete cardReserved[msg.sender];
        delete cardReserved[opponent];
        delete betReservedSize[msg.sender];
        delete betReservedSize[opponent];
    }

    function ForceWin() public {
        if (cardReserved[msg.sender] == 0) {
            revert("Must have selected a card");
        }
        uint256 lastCallTime = drawTime[msg.sender];
        if (lastCallTime == 0 || block.timestamp < lastCallTime + 1800) {
            revert("Opponent has 30 minutes to draw a card");
        }
        address opponent = userReservedToOpponent[msg.sender];
        if (cardReserved[opponent] != 0) {
            revert("Opponent has drawn a card");
        }
        uint256 totalBet = betReservedSize[msg.sender] + betReservedSize[opponent];

        warToken.gameMint(msg.sender, totalBet);
        delete userReservedPool[opponent];
        delete userReservedPool[msg.sender];
        delete userReservedToOpponent[msg.sender];
        delete opponentReservedToUser[msg.sender];
        delete userReservedToOpponent[opponent];
        delete opponentReservedToUser[opponent];
        delete cardReserved[msg.sender];
        delete cardReserved[opponent];
        delete betReservedSize[msg.sender];
        delete betReservedSize[opponent];
        delete drawTime[msg.sender];
        delete drawTime[opponent];
    }
}
