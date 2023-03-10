// test: 0xcC9De99b32750a0550380cb8495588ca2f48d533
// previous: 0x37Ae76D5c3AdB25790F64215062E512a9d2262b7
// latest: 0xB383940282D6624b9e7F8e4e1AEFD78e27A987F6
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface WarToken {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract WARGAME is Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

    uint256 public totalPlays;

    /******************/

    /* Regular pool */
    mapping(address => bytes32) public userId;
    mapping(bytes32 => address) public requestUser;
    mapping(bytes32 => uint256) public randomNumber;
    mapping(address => uint256) public betsize;
    mapping(address => uint256) public userHighscore;

    mapping(address => bool) public userPool;
    mapping(uint256 => address) public userIndex;
    mapping(address => address) public userToOpponent;
    mapping(address => address) public opponentToUser;
    mapping(address => uint256) public card;
    mapping(address => uint256) public drawTime;
    mapping(address => bool) public inGame;

    /* 50 pool*/            
    mapping(address => bool) public userFiftyPool;
    mapping(uint256 => address) public userFiftyIndex;        
    uint256 poolFiftyIndex;

    /* 100 pool*/            
    mapping(address => bool) public userHundredPool;
    mapping(uint256 => address) public userHundredIndex;        
    uint256 poolHundredIndex;

    /* 500 pool*/            
    mapping(address => bool) public userLargePool;
    mapping(uint256 => address) public userLargeIndex;       
    uint256 poolLargeIndex;

    uint256 public poolIndex;

    uint256 public highscore;
    address public highscoreHolder;

    address public airnode;
    bytes32 public endpointIdUint256;
    address public sponsorWallet;

    uint256 public qfee = 50000000000000;
    uint256 waitTime = 600; //1800;
    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed player,
        address indexed opponent,
        uint256 myCard,
        uint256 theirCard,
        bool won,
        uint256 winAmount,
        uint256 oppWinAmount
    );

    event EnteredPool(address indexed player);
    event EnteredFiftyPool(address indexed player);
    event EnteredHundredPool(address indexed player);    
    event EnteredLargePool(address indexed player);

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256 response
    );

    bool gameActive;

    address botContract;

    constructor(address _airnodeRrp, address _warTokenAddress)
        RrpRequesterV0(_airnodeRrp)
    {
        warToken = WarToken(_warTokenAddress);
    }

    modifier onlyOwnerBot() {
        require(
            (msg.sender ==owner()) || (msg.sender == botContract),
            "Only Owner or Bot"
        );
        _;
    }

    function setBot(address _botContract) public onlyOwner {
        botContract = _botContract;
    }

    function setQfee(uint256 _qfee) public onlyOwner {
        require(_qfee <= 150000000000000, "Dont set fee too high");
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

    function enterPool(uint256 _amount) public payable nonReentrant {
        require(!inGame[msg.sender], "Can only enter one pool at a time");
        require(_amount > 0, "Must include a bet amount");
        require(
            msg.value >= qfee,
            "Must small gas fee for the random number generator"
        );
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        //address payable sendAddress = payable(sponsorWallet);        
        payable(sponsorWallet).transfer(qfee);
        userPool[msg.sender] = true;
        inGame[msg.sender] = true;
        userIndex[poolIndex+1] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;

        warToken.gameBurn(msg.sender, _amount);        
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
        ++poolIndex;
    }

    function leavePool(address user) internal {
        require(userPool[user], "Not in general pool");
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 1; i <= poolIndex; i++) {
            if (userIndex[i] == user) {
                userIndexToDelete = i;
                delete userIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i <= poolIndex; i++) {
            userIndex[i] = userIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userIndex[poolIndex];
        // Delete the user from userPool
        delete userPool[user];
        // Decrement the pool index
        --poolIndex;
    }

    function ForceLeavePool() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!userPool[msg.sender]) {
            revert("Cannot leave Pool if you arent in the pool");
        }
        if (userToOpponent[msg.sender] == address(0)) {
            warToken.gameMint(msg.sender, betsize[msg.sender]);
        }
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete inGame[msg.sender];
        leavePool(msg.sender);
    }

    function Draw() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        require(
            poolIndex >= 2 || opponentToUser[msg.sender] != address(0),
            "Pool is low. wait for more players to enter"
        );
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            card[msg.sender] == 0,
            "Card has been assigned, reveal to view results"
        );

        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;
        uint256 opponentNum;
        address opponent;
        if (opponentToUser[msg.sender] == address(0)) {
            opponentNum = (randomNumber[requestId] % (poolIndex-1)+1);
            opponent = userIndex[opponentNum];            
            if (userIndex[opponentNum] == msg.sender) {
                if (opponentNum >= (poolIndex)) {
                    --opponentNum;
                    if (opponentNum == 0) {
                        revert(
                            "Pool has emptied while you were drawing. please try to draw again"
                        );
                    }
                } else {
                    ++opponentNum;
                }
            }
            opponent = userIndex[opponentNum];            
            userToOpponent[msg.sender] = opponent;
            opponentToUser[opponent] = msg.sender;
            userToOpponent[opponent] = msg.sender;
            opponentToUser[msg.sender] = opponent;
        }
        else
        {
            opponent = opponentToUser[msg.sender];
        }

        card[msg.sender] = secretnum;
        drawTime[msg.sender] = block.timestamp;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete userId[msg.sender];
        if (userPool[msg.sender]) {            
            leavePool(msg.sender);            
        }
        if (userPool[userToOpponent[msg.sender]]) {
            leavePool(userToOpponent[msg.sender]);
        }
    }

    function enterFiftyPool(uint256 _amount) public payable nonReentrant {
        require(!inGame[msg.sender], "Can only enter one pool at a time");
        require(_amount == 50000000000000000000, "Must bet 100 tokens");
        require(
            msg.value >= qfee,
            "Must small gas fee for the random number generator"
        );
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        //address payable sendAddress = payable(sponsorWallet);        
        payable(sponsorWallet).transfer(qfee);
        userFiftyPool[msg.sender] = true;
        inGame[msg.sender] = true;
        userFiftyIndex[poolFiftyIndex+1] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;

        warToken.gameBurn(msg.sender, _amount);     
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
        ++poolFiftyIndex;
    }

    function leaveFiftyPool(address user) internal {
        require(userFiftyPool[user], "Not in any pool");
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 1; i <= poolFiftyIndex; i++) {
            if (userFiftyIndex[i] == user) {
                userIndexToDelete = i;
                delete userFiftyIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i <= poolFiftyIndex; i++) {
            userFiftyIndex[i] = userFiftyIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userFiftyIndex[poolFiftyIndex];
        // Delete the user from userPool
        delete userFiftyPool[user];
        // Decrement the pool index
        --poolFiftyIndex;
    }

    function ForceFiftyLeavePool() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!userFiftyPool[msg.sender]) {
            revert("Cannot leave Pool if you arent in the pool");
        }
        if (userToOpponent[msg.sender] == address(0)) {
            warToken.gameMint(msg.sender, betsize[msg.sender]);
        }
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete inGame[msg.sender];
        leaveFiftyPool(msg.sender);
    }

    function DrawFifty() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!inGame[msg.sender]) {
            revert("Must be in a game to draw");
        }
        require(
            poolFiftyIndex >= 2 || opponentToUser[msg.sender] != address(0),
            "Pool is low. wait for more players to enter"
        );
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            card[msg.sender] == 0,
            "Card has been assigned, reveal to view results"
        );

        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;
        uint256 opponentNum;
        address opponent;
        if (opponentToUser[msg.sender] == address(0)) {
            opponentNum = (randomNumber[requestId] % (poolFiftyIndex-1)+1);
            opponent = userFiftyIndex[opponentNum];            
            if (userFiftyIndex[opponentNum] == msg.sender) {
                if (opponentNum >= (poolFiftyIndex)) {
                    --opponentNum;
                    if (opponentNum == 0) {
                        revert(
                            "Pool has emptied while you were drawing. please try to draw again"
                        );
                    }
                } else {
                    ++opponentNum;
                }
            }
            opponent = userIndex[opponentNum];            
            userToOpponent[msg.sender] = opponent;
            opponentToUser[opponent] = msg.sender;
            userToOpponent[opponent] = msg.sender;
            opponentToUser[msg.sender] = opponent;
        }
        else
        {
            opponent = opponentToUser[msg.sender];
        }

        card[msg.sender] = secretnum;
        drawTime[msg.sender] = block.timestamp;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete userId[msg.sender];
        if (userFiftyPool[msg.sender]) {            
            leaveFiftyPool(msg.sender);            
        }
        if (userFiftyPool[userToOpponent[msg.sender]]) {
            leaveFiftyPool(userToOpponent[msg.sender]);
        }
    }

    function enterHundredPool(uint256 _amount) public payable nonReentrant {
        require(!inGame[msg.sender], "Can only enter one pool at a time");
        require(_amount == 100000000000000000000, "Must bet 100 tokens");
        require(
            msg.value >= qfee,
            "Must small gas fee for the random number generator"
        );
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        //address payable sendAddress = payable(sponsorWallet);        
        payable(sponsorWallet).transfer(qfee);
        userHundredPool[msg.sender] = true;
        inGame[msg.sender] = true;
        userHundredIndex[poolHundredIndex+1] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;

        warToken.gameBurn(msg.sender, _amount);     
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
        ++poolHundredIndex;
    }

    function leaveHundredPool(address user) internal {
        require(userHundredPool[user], "Not in any pool");
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 1; i <= poolFiftyIndex; i++) {
            if (userHundredIndex[i] == user) {
                userIndexToDelete = i;
                delete userHundredIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i <= poolHundredIndex; i++) {
            userHundredIndex[i] = userHundredIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userHundredIndex[poolHundredIndex];
        // Delete the user from userPool
        delete userHundredPool[user];
        // Decrement the pool index
        --poolHundredIndex;
    }

    function ForceHundredLeavePool() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!userHundredPool[msg.sender]) {
            revert("Cannot leave Pool if you arent in the pool");
        }
        if (userToOpponent[msg.sender] == address(0)) {
            warToken.gameMint(msg.sender, betsize[msg.sender]);
        }
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete inGame[msg.sender];
        leaveHundredPool(msg.sender);
    }

    function DrawHundred() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!inGame[msg.sender]) {
            revert("Must be in a game to draw");
        }
        require(
            poolHundredIndex >= 2 || opponentToUser[msg.sender] != address(0),
            "Pool is low. wait for more players to enter"
        );
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            card[msg.sender] == 0,
            "Card has been assigned, reveal to view results"
        );

        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;
        uint256 opponentNum;
        address opponent;
        if (opponentToUser[msg.sender] == address(0)) {
            opponentNum = (randomNumber[requestId] % (poolFiftyIndex-1)+1);
            opponent = userHundredIndex[opponentNum];            
            if (userHundredIndex[opponentNum] == msg.sender) {
                if (opponentNum >= (poolFiftyIndex)) {
                    --opponentNum;
                    if (opponentNum == 0) {
                        revert(
                            "Pool has emptied while you were drawing. please try to draw again"
                        );
                    }
                } else {
                    ++opponentNum;
                }
            }
            opponent = userHundredIndex[opponentNum];            
            userToOpponent[msg.sender] = opponent;
            opponentToUser[opponent] = msg.sender;
            userToOpponent[opponent] = msg.sender;
            opponentToUser[msg.sender] = opponent;
        }
        else
        {
            opponent = opponentToUser[msg.sender];
        }

        card[msg.sender] = secretnum;
        drawTime[msg.sender] = block.timestamp;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete userId[msg.sender];
        if (userHundredPool[msg.sender]) {            
            leaveHundredPool(msg.sender);            
        }
        if (userHundredPool[userToOpponent[msg.sender]]) {
            leaveHundredPool(userToOpponent[msg.sender]);
        }
    }

    function enterLargePool(uint256 _amount) public payable nonReentrant {
        require(!inGame[msg.sender], "Can only enter one pool at a time");
        require(_amount == 500000000000000000000, "Must bet 100 tokens");
        require(
            msg.value >= qfee,
            "Must small gas fee for the random number generator"
        );
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        //address payable sendAddress = payable(sponsorWallet);        
        payable(sponsorWallet).transfer(qfee);
        userLargePool[msg.sender] = true;
        inGame[msg.sender] = true;
        userHundredIndex[poolLargeIndex+1] = msg.sender;
        makeRequestUint256(msg.sender);
        betsize[msg.sender] = _amount;

        warToken.gameBurn(msg.sender, _amount);     
        emit bet(msg.sender, _amount);
        emit EnteredPool(msg.sender);
        ++poolLargeIndex;
    }

    function leaveLargePool(address user) internal {
        require(userLargePool[user], "Not in any pool");
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        // Find the index of the user in userIndex and delete it
        uint256 userIndexToDelete;
        for (uint256 i = 1; i <= poolLargeIndex; i++) {
            if (userLargeIndex[i] == user) {
                userIndexToDelete = i;
                delete userLargeIndex[i];
                break;
            }
        }

        // Shift all the elements after the deleted index to the left by one position
        for (uint256 i = userIndexToDelete; i <= poolLargeIndex; i++) {
            userLargeIndex[i] = userLargeIndex[i + 1];
        }

        // Delete the last element of userIndex
        delete userLargeIndex[poolLargeIndex];
        // Delete the user from userPool
        delete userLargePool[user];
        // Decrement the pool index
        --poolLargeIndex;
    }

    function ForceLargeLeavePool() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!userLargePool[msg.sender]) {
            revert("Cannot leave Pool if you arent in the pool");
        }
        if (userToOpponent[msg.sender] == address(0)) {
            warToken.gameMint(msg.sender, betsize[msg.sender]);
        }
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete inGame[msg.sender];
        leaveLargePool(msg.sender);
    }

    function DrawLarge() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!inGame[msg.sender]) {
            revert("Must be in a game to draw");
        }
        require(
            poolLargeIndex >= 2 || opponentToUser[msg.sender] != address(0),
            "Pool is low. wait for more players to enter"
        );
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(
            (randomNumber[userId[msg.sender]] != uint256(0)),
            "Random number not ready, try again."
        );
        require(
            card[msg.sender] == 0,
            "Card has been assigned, reveal to view results"
        );

        bytes32 requestId = userId[msg.sender];
        uint256 secretnum = (randomNumber[requestId] % 12) + 1;
        uint256 opponentNum;
        address opponent;
        if (opponentToUser[msg.sender] == address(0)) {
            opponentNum = (randomNumber[requestId] % (poolLargeIndex-1)+1);
            opponent = userHundredIndex[opponentNum];            
            if (userLargeIndex[opponentNum] == msg.sender) {
                if (opponentNum >= (poolLargeIndex)) {
                    --opponentNum;
                    if (opponentNum == 0) {
                        revert(
                            "Pool has emptied while you were drawing. please try to draw again"
                        );
                    }
                } else {
                    ++opponentNum;
                }
            }
            opponent = userLargeIndex[opponentNum];            
            userToOpponent[msg.sender] = opponent;
            opponentToUser[opponent] = msg.sender;
            userToOpponent[opponent] = msg.sender;
            opponentToUser[msg.sender] = opponent;
        }
        else
        {
            opponent = opponentToUser[msg.sender];
        }

        card[msg.sender] = secretnum;
        drawTime[msg.sender] = block.timestamp;
        delete randomNumber[requestId];
        delete requestUser[requestId];
        delete userId[msg.sender];
        if (userLargePool[msg.sender]) {            
            leaveLargePool(msg.sender);            
        }
        if (userLargePool[userToOpponent[msg.sender]]) {
            leaveLargePool(userToOpponent[msg.sender]);
        }
    }

    function OpponentIssue() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (card[msg.sender] != 0 && userToOpponent[msg.sender] != address(0)) {
            revert("Opponent is selected. wait for reveal");
        }
        if (!inGame[msg.sender]) {
            revert("Must be in game");
        }
        if (userPool[msg.sender] || userFiftyPool[msg.sender]) {
            revert("Use Force Leave pool function to leave the pool");
        }
        warToken.gameMint(msg.sender, betsize[msg.sender]);
        delete randomNumber[userId[msg.sender]];
        delete requestUser[userId[msg.sender]];
        delete betsize[msg.sender];
        delete userId[msg.sender];
        delete card[msg.sender];
        delete drawTime[msg.sender];
        delete inGame[msg.sender];
    }

    function Reveal() public nonReentrant {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        require(
            card[msg.sender] != 0,
            "Card has not been assigned, draw your card."
        );
        address opponent = userToOpponent[msg.sender];
        require(card[opponent] != 0, "Opponent has not drawn a card");
        uint256 myCard = card[msg.sender];
        uint256 theirCard = card[opponent];
        uint256 userBet = betsize[msg.sender];
        uint256 opponentBet = betsize[opponent];

        uint256 payoutWin;
        uint256 loseDelta;
        uint256 winDelta;        
        uint256 emitWin;
        uint256 emitLose;
        if (userBet >= opponentBet) {
            payoutWin = userBet + opponentBet;
            loseDelta = userBet - opponentBet;  
            emitLose = opponentBet;          
        } else {
            payoutWin = userBet + userBet;
            winDelta = opponentBet - userBet;
            emitLose = userBet;
        }
        if (myCard > theirCard) {            
            if (payoutWin > highscore) {
                highscore = payoutWin;
                highscoreHolder = msg.sender;
            }
            if (payoutWin > userHighscore[msg.sender]) {
                userHighscore[msg.sender] = payoutWin;
            }
            emitWin = (payoutWin - userBet);
            
            emit win(msg.sender, opponent, myCard, theirCard, true, emitWin, emitLose);
            warToken.gameMint(msg.sender, payoutWin);
            warToken.gameMint(opponent, winDelta);
        } else if (myCard == theirCard) {
            emit win(
                msg.sender,
                opponent,
                myCard,
                theirCard,
                false,
                0,
                0
            );
            warToken.gameMint(msg.sender, userBet);
            warToken.gameMint(opponent, opponentBet);
        } else {
            warToken.gameMint(msg.sender, loseDelta);
            uint256 payopponent = (opponentBet + userBet) - loseDelta;
            warToken.gameMint(opponent, payopponent);
            emitWin = (payopponent - opponentBet);
            emit win(
                msg.sender,
                opponent,
                myCard,
                theirCard,
                false,
                emitLose,
                emitWin
            );
            if (payopponent > highscore) {
                highscore = payopponent;
                highscoreHolder = opponent;
            }
            if (payopponent > userHighscore[opponent]) {
                userHighscore[opponent] = payopponent;
            }
        }
        ++totalPlays;        
        delete userToOpponent[msg.sender];
        delete opponentToUser[msg.sender];
        delete userToOpponent[opponent];
        delete opponentToUser[opponent];
        delete card[msg.sender];
        delete card[opponent];
        delete betsize[msg.sender];
        delete betsize[opponent];
        delete drawTime[msg.sender];
        delete drawTime[opponent];
        delete inGame[msg.sender];
        delete inGame[opponent];
        delete userPool[opponent];
        delete userPool[msg.sender];
        delete userFiftyPool[opponent];
        delete userFiftyPool[msg.sender];
        delete userHundredPool[opponent];
        delete userHundredPool[msg.sender];
        delete userLargePool[opponent];
        delete userLargePool[msg.sender];
    }

    function ForceWin() public {
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (waitTime==0) {
            revert("Ask Dev to Set a Wait Time");
        }
        if (card[msg.sender] == 0 && !inGame[msg.sender]) {
            revert("Must have selected a card");
        }
        uint256 lastCallTime = drawTime[msg.sender];
        if (lastCallTime == 0 || block.timestamp < (lastCallTime + waitTime)) {
            revert("Opponent has 30 minutes to draw a card");
        }
        address opponent = userToOpponent[msg.sender];
        if (card[opponent] != 0) {
            revert("Opponent has drawn a card");
        }
        uint256 myCard = card[msg.sender];
        uint256 theirCard = card[opponent];
        uint256 totalBet = betsize[msg.sender] + betsize[opponent];
        uint256 opponentBet = betsize[opponent];
        bytes32 oppRequestId = userId[opponent];

        emit win(msg.sender, opponent, myCard, theirCard, true, totalBet, opponentBet);

        warToken.gameMint(msg.sender, totalBet);

        delete randomNumber[oppRequestId];
        delete requestUser[oppRequestId];
        delete userId[msg.sender];
        delete userId[opponent];
        delete userPool[opponent];
        delete userPool[msg.sender];
        delete userFiftyPool[opponent];
        delete userFiftyPool[msg.sender];
        delete userHundredPool[opponent];
        delete userHundredPool[msg.sender];
        delete userLargePool[opponent];
        delete userLargePool[msg.sender];
        delete userToOpponent[msg.sender];
        delete opponentToUser[msg.sender];
        delete userToOpponent[opponent];
        delete opponentToUser[opponent];
        delete card[msg.sender];
        delete card[opponent];
        delete betsize[msg.sender];
        delete betsize[opponent];
        delete drawTime[msg.sender];
        delete drawTime[opponent];
        delete inGame[msg.sender];
        delete inGame[opponent];
    }

    function ChangeStatus(bool _newStatus) public onlyOwnerBot {
        gameActive = _newStatus;
    }

    function ChangeWinTime(uint256 _waitTime) public onlyOwner {
        waitTime = _waitTime;
    }

    function fixGameIndex() external onlyOwnerBot {
        address[] memory nonZeroIndices = new address[](poolIndex + 1);
        uint256 count = 0;
        uint256 userIndexToDelete;

        // Collect all the non-zero indices from userIndex
        for (uint256 i = 1; i <= poolIndex; i++) {
            if (userIndex[i] != address(0)) {
                nonZeroIndices[count] = userIndex[i];
                count++;
            }
        }

        // Update userIndex with the non-zero indices and adjust poolIndex accordingly
        if (count > 0) {
            for (uint256 i = 0; i < count; i++) {
                userIndex[i + 1] = nonZeroIndices[i];
            }
            poolIndex = count;
        } else {
            poolIndex = 0;
        }

        // Delete any remaining elements in userIndex
        for (uint256 i = count + 1; i <= poolIndex; i++) {
            delete userIndex[i];
        }
    }
}
