pragma solidity ^0.8.0;

import 'openzeppelin-solidity/contracts/utils/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/utils/Context.sol';
import 'openzeppelin-solidity/contracts/access/Ownable.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/ITimeStaking.sol';
import './interfaces/IUniswapV2Router.sol';
import './interfaces/IMooCurveZap.sol';

contract TimeOptimizer is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    
    uint256 constant MAX_INT = 2**256 - 1;

    // Memo Under Management (MUM)
    uint256 public mum = 0;
   
    /**
     * @dev Tokens addresses
     */    
    address public MEMO = 0x136acd46c134e8269052c62a67042d6bdedde3c9;
    address public TIME = 0xb54f16fB19478766A268F172C9480f8da1a7c9C3;
    address public WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    /**
     * @dev Interfacing contracts addresses
     */
    address public timeStakingAddr = 0x4456B87Af11e87E329AB7d7C7A246ed1aC2168B9;
    address public uniV2RouterAddr = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address public mooCurveZapAddr;
    address public parentFactory;

    /**
     * @dev Initializes the strategy for the given protocol
     */
    constructor(
        address _mooCurveZapAddr
    ) { 
        mooCurveZapAddr = _mooCurveZapAddr;
        parentFactory = msg.sender;

        IERC20(MEMO).safeApprove(timeStakingAddr, 0);
        IERC20(MEMO).safeApprove(timeStakingAddr, MAX_INT);
        IERC20(TIME).safeApprove(uniV2RouterAddr, 0);
        IERC20(TIME).safeApprove(uniV2RouterAddr, MAX_INT);        
    }

    function deposit(uint256 _amount) external onlyOwner {
        require(IERC20(MEMO).balanceOf(address(msg.sender)) >= _amount, "Insufficient balance");
        IERC20(MEMO).safeTransferFrom(msg.sender, address(this), _amount);
        mum = mum.add(_amount);
    }

    function withdraw(uint256 _amount) external onlyOwner {
        require(IERC20(MEMO).balanceOf(address(this)) >= _amount, "Insufficient balance");
        IERC20(MEMO).safeTransfer(msg.sender, _amount);
        mum = IERC20(MEMO).balanceOf(address(this));
    }

    function reinvestInToken(address _desiredToken, uint256 _basisPoint) external onlyOwner {
        require(_desiredToken != MEMO && _desiredToken != TIME, "Cannot reinvest into MEMO or TIME");
        require(_basisPoint <= 10000, "Incorrect Basis Point parameter");

        uint256 profit = (IERC20(MEMO).balanceOf(address(this))).sub(mum);
        uint256 amountToSwap = profit.mul(_basisPoint).div(10000);

        ITimeStaking(timeStakingAddr).unstake(amountToSwap, true);
        mum = IERC20(MEMO).balanceOf(address(this));
        _swapToken(_desiredToken);
        IERC20(_desiredToken).safeTransfer(msg.sender, IERC20(_desiredToken).balanceOf(address(this)));
    }

    function reinvestInProduct(address _desiredToken, uint256 _basisPoint) external onlyOwner {
        require(_desiredToken != MEMO, "Cannot reinvest into MEMO");
        require(_basisPoint <= 10000, "Incorrect Basis Point parameter");

        uint256 profit = (IERC20(MEMO).balanceOf(address(this))).sub(mum);
        uint256 amountToSwap = profit.mul(_basisPoint).div(10000);

        ITimeStaking(timeStakingAddr).unstake(amountToSwap, true);
        mum = IERC20(MEMO).balanceOf(address(this));
        _swapToken(_desiredToken);
        _reinvestInMooCurve(_desiredToken);
    }
    
    function recoverERC20(address _ERC20) external onlyOwner {
        if(IERC20(_ERC20).balanceOf(address(this)) > 0){
            IERC20(_ERC20).safeTransfer(msg.sender, IERC20(_ERC20).balanceOf(address(this)));
        }        
    }

    function setUniV2Router(address _uniV2Router) external onlyOwner {
        uniV2RouterAddr = _uniV2Router;
    }

    function _swapToken(address _desiredToken) internal {
        require(IERC20(TIME).balanceOf(address(this)) > 0);
        address[] memory timeToWeth = new address[](2);
        timeToWeth[0] = TIME;
        timeToWeth[1] = WETH;
        IUniswapV2Router(uniV2RouterAddr).swapExactTokensForTokens(
            IERC20(TIME).balanceOf(address(this)),
            0,
            timeToWeth,
            address(this),
            block.timestamp.add(600)
        );
        address[] memory wethToDesiredToken = new address[](2);
        wethToDesiredToken[0] = WETH;
        wethToDesiredToken[1] = _desiredToken;
        IERC20(WETH).safeApprove(uniV2RouterAddr, MAX_INT);        
        IUniswapV2Router(uniV2RouterAddr).swapExactTokensForTokens(
            IERC20(WETH).balanceOf(address(this)),
            0,
            wethToDesiredToken,
            address(this),
            block.timestamp.add(600)
        );
    }

    function _reinvestInMooCurve(address _tokenToInvest) internal {
        uint256 amountToInvest = IERC20(_tokenToInvest).balanceOf(address(this));
        IERC20(_tokenToInvest).approve(mooCurveZapAddr, amountToInvest);
        IMooCurveZap(mooCurveZapAddr).zap(_tokenToInvest, amountToInvest);
        address mooToken = IMooCurveZap(mooCurveZapAddr).beefyVault();
        IERC20(mooToken).safeTransfer(msg.sender, IERC20(mooToken).balanceOf(address(this)));
    }
    
}    