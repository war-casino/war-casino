// test: 0xcC9De99b32750a0550380cb8495588ca2f48d533
// previous: 0x20c375C04e22E600A2BD4Bb9c4499483942Fa7C7
// latest: 0xa1646B20BC827a02B92Cf0314Cea656665BDb571
pragma solidity ^0.8.9;
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface WarToken {
    function gameMint(address _to, uint256 _amount) external;

    function gameBurn(address _to, uint256 _amount) external;
}

contract WARBOTS is Ownable, ReentrancyGuard, RrpRequesterV0 {
    using SafeMath for uint256;

    uint256 public totalPlays;

    /******************/

    mapping(address => bytes32) public userId;
    mapping(bytes32 => address) public requestUser;
    mapping(bytes32 => uint256[]) public randomNumberArray;
    mapping(address => uint256) public betsize;
    // mapping(address => uint256) public userHighscore;    

    mapping(address => bool) public inGame;    
    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;

    uint256 public poolIndex;

    uint256 public highscore;
    address public highscoreHolder;

    address public airnode;
    bytes32 public endpointIdUint256Array;
    address public sponsorWallet;

    uint256 public qfee = 100000000000000;                          
// 180000000000000
    WarToken warToken;

    event bet(address indexed from, uint256 amount);
    event win(
        address indexed from,
        uint256 myCard,
        uint256 theirCard,
        bool won,
        uint256 Amount        
    );

    event EnteredPool(address indexed player);

    event RequestedUint256Array(bytes32 indexed requestId, uint256 size);
    event ReceivedUint256Array(
        address indexed requestAddress,
        bytes32 indexed requestId,
        uint256[] response
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
        require(_qfee <= 200000000000000, "Dont set fee too high");
        require(_qfee >= 50000000000000, "Dont set fee too low");
        qfee = _qfee;
    }

    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256Array,
        address _sponsorWallet
    ) external onlyOwner {
        airnode = _airnode;
        endpointIdUint256Array = _endpointIdUint256Array;
        sponsorWallet = _sponsorWallet;
    }

    function makeRequestUint256Array(address userAddress, uint256 size) internal {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256Array,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256Array.selector,
            // Using Airnode ABI to encode the parameters
            abi.encode(bytes32("1u"), bytes32("size"), size)
        );
        expectingRequestWithIdToBeFulfilled[requestId] = true;
        userId[userAddress] = requestId;
        requestUser[requestId] = userAddress;
        uint256[] memory tempZero;
        tempZero = new uint256[](2);
        tempZero[0] = uint256(0);
        tempZero[1] = uint256(0);
        randomNumberArray[requestId] = tempZero;
        emit RequestedUint256Array(requestId, size);
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param data ABI-encoded response
    function fulfillUint256Array(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(
            expectingRequestWithIdToBeFulfilled[requestId],
            "Request ID not known"
        );
        address userAddress = requestUser[requestId];
        expectingRequestWithIdToBeFulfilled[requestId] = false;
        uint256[] memory qrngUint256Array = abi.decode(data, (uint256[]));
        randomNumberArray[requestId] = qrngUint256Array;
        // Do what you want with `qrngUint256Array` here...
        emit ReceivedUint256Array(userAddress, requestId, qrngUint256Array);
    }    
    function DrawCard(uint256 _amount) public payable nonReentrant {
        require(!inGame[msg.sender], "Can only enter one pool at a time");
        require(_amount > 0, "Must include a bet amount");
        require(
            msg.value >= qfee,
            "Must small gas fee for the random number generator"
        );
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }

        betsize[msg.sender] = _amount;        
        payable(sponsorWallet).transfer(qfee);
        inGame[msg.sender] = true;        
        makeRequestUint256Array(msg.sender,2);        
        
        warToken.gameBurn(msg.sender, _amount);        
        emit bet(msg.sender, _amount);               
    }

    function RevealResults() public nonReentrant {        
        if (!gameActive) {
            revert("Game has been temporarily Paused");
        }
        if (!inGame[msg.sender])
        {
            revert("Not in A Game");
        }
        bytes32 requestId = userId[msg.sender];        
        require((randomNumberArray[requestId][0] != uint256(0)) && (randomNumberArray[requestId][1] != uint256(0)),"Random number not ready, try again.");
        uint256 myCard = (randomNumberArray[requestId][0] % 18) + 1;
        uint256 botCard = (randomNumberArray[requestId][1] % 19) + 1;

        uint256 userBet = betsize[msg.sender];    
        uint256 winAmount = userBet*2;

        if (myCard > botCard) {                                    
            emit win(msg.sender, myCard, botCard, true, userBet);
            warToken.gameMint(msg.sender, winAmount);  
            if (userBet > highscore) {
                highscore = userBet;
                highscoreHolder = msg.sender;
            }          
        } else if (myCard == botCard) {
            emit win(
                msg.sender,
                myCard,
                botCard,
                false,
                userBet
            );
            warToken.gameMint(msg.sender, userBet);
        } else {                        
            emit win(
                msg.sender,
                myCard,
                botCard,
                false,
                userBet                
            );            
        }
        ++totalPlays;
        delete requestUser[requestId];
        randomNumberArray[requestId][0] = uint256(0);
        randomNumberArray[requestId][1] = uint256(0);
        delete userId[msg.sender];        
        delete betsize[msg.sender];
        delete inGame[msg.sender];
    }
    
    function ChangeStatus(bool _newStatus) public onlyOwnerBot {
        gameActive = _newStatus;
    }


    function leaveGame()
    public
    nonReentrant
    {           
        if (!inGame[msg.sender])
        {
            revert("Not in a game");
        }
        bytes32 requestId = userId[msg.sender];   
        uint256 userBet = betsize[msg.sender];
        if(userBet != uint256(0))
        {
            warToken.gameMint(msg.sender,betsize[msg.sender]);
        }
        

        delete requestUser[requestId];        
        randomNumberArray[requestId][0] = uint256(0);
        randomNumberArray[requestId][1] = uint256(0);       
        delete userId[msg.sender];        
        delete betsize[msg.sender];
        delete inGame[msg.sender];       
    }



}

