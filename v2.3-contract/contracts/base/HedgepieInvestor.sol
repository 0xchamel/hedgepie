// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/HedgepieLibraryBsc.sol";
import "../interfaces/IYBNFT.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IHedgepieAuthority.sol";
import "../interfaces/IHedgepieAdapterList.sol";
import "../interfaces/IStargateReceiver.sol";

import "./HedgepieAccessControlled.sol";

contract HedgepieInvestor is ReentrancyGuardUpgradeable, HedgepieAccessControlled, IStargateReceiver {
    using SafeERC20 for IERC20;

    struct PendingWithdraw {
        address addr; // adapter address
        uint256 amount; // total invested to adapter in usd
        uint256 totalStaked; // total staked to adapter
    }

    struct UserInfo {
        uint256 userShare; // user share amount
        uint256 amount; // user deposit amount
        uint256 rewardDebt; // user reward amount
    }

    struct TokenInfo {
        uint256 totalStaked; // total staked in usd
        uint256 accRewardShare; // reward share per account
    }

    // token id => token info
    mapping(uint256 => TokenInfo) public tokenInfos;

    // address => user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    // token id => adapter address => user address => pending withdraw info
    mapping(uint256 => mapping(address => mapping(address => PendingWithdraw))) public pWithdrawals;

    // treasury address
    address public treasury;

    /// @dev events
    event Deposited(address indexed user, address nft, uint256 nftId, uint256 amount);
    event Withdrawn(address indexed user, address nft, uint256 nftId, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event TreasuryUpdated(address treasury);
    event sgReceived(uint16 chainId, bytes srcAddress, uint256 nonce, address token, uint256 amount, bytes payload);

    modifier onlyValidNFT(uint256 _tokenId) {
        require(IYBNFT(authority.hYBNFT()).exists(_tokenId), "Error: nft tokenId is invalid");
        _;
    }

    modifier onlyYBNft() {
        require(msg.sender == authority.hYBNFT(), "Error: YBNFT address mismatch");
        _;
    }

    /**
     * @notice initialize
     * @param _treasury  address of treasury
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    function initialize(address _treasury, address _hedgepieAuthority) external initializer {
        require(_treasury != address(0), "Error: treasury address missing");

        __ReentrancyGuard_init();
        __HedgepieAccessControlled_init(IHedgepieAuthority(_hedgepieAuthority));

        treasury = _treasury;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId  YBNft token id
     */
    function deposit(uint256 _tokenId) external payable whenNotPaused nonReentrant onlyValidNFT(_tokenId) {
        require(msg.value != 0, "Error: Insufficient BNB");
        UserInfo storage userInfo = userInfos[_tokenId][msg.sender];
        TokenInfo storage tokenInfo = tokenInfos[_tokenId];

        // 1. claim reward from adapters
        _calcReward(_tokenId);

        // 2. deposit to adapters
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        uint256 totalUsed;
        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.AdapterParam memory adapter = adapterInfos[i];

            uint256 amountIn = (msg.value * adapter.allocation) / 1e4;
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(adapter.addr);

            if (amountIn != 0) {
                if (locked) {
                    (bool success, ) = payable(msg.sender).call{value: amountIn}("");
                    require(success, "Error: refund");
                } else {
                    IAdapter(adapter.addr).deposit{value: amountIn}(_tokenId);
                    totalUsed += amountIn;
                }
            }
        }

        // 3. update user & token info saved in investor
        uint256 investedUSDT = (totalUsed * HedgepieLibraryBsc.getBNBPrice()) / 1e18;
        userInfo.amount += investedUSDT;
        tokenInfo.totalStaked += investedUSDT;

        // 4. update token info in YBNFT
        IYBNFT(authority.hYBNFT()).updateInfo(IYBNFT.UpdateInfo(_tokenId, investedUSDT, msg.sender, true));

        // 5. emit events
        emit Deposited(msg.sender, authority.hYBNFT(), _tokenId, totalUsed);
    }

    /**
     * @notice Deposit with BNB instead of other user
     * @param _tokenId  YBNft token id
     */
    function depositOnBehalf(
        uint256 _tokenId,
        address _user
    ) public payable whenNotPaused nonReentrant onlyValidNFT(_tokenId) {
        require(msg.value != 0, "Error: Insufficient BNB");
        UserInfo storage userInfo = userInfos[_tokenId][_user];
        TokenInfo storage tokenInfo = tokenInfos[_tokenId];

        // 1. claim reward from adapters
        _calcReward(_tokenId);

        // 2. deposit to adapters
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        uint256 totalUsed;
        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.AdapterParam memory adapter = adapterInfos[i];

            uint256 amountIn = (msg.value * adapter.allocation) / 1e4;
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(adapter.addr);

            if (amountIn != 0) {
                if (locked) {
                    (bool success, ) = payable(_user).call{value: amountIn}("");
                    require(success, "Error: refund");
                } else {
                    IAdapter(adapter.addr).deposit{value: amountIn}(_tokenId);
                    totalUsed += amountIn;
                }
            }
        }

        // 3. update user & token info saved in investor
        uint256 investedUSDT = (totalUsed * HedgepieLibraryBsc.getBNBPrice()) / 1e18;
        userInfo.amount += investedUSDT;
        tokenInfo.totalStaked += investedUSDT;

        // 4. update token info in YBNFT
        IYBNFT(authority.hYBNFT()).updateInfo(IYBNFT.UpdateInfo(_tokenId, investedUSDT, _user, true));

        // 5. emit events
        emit Deposited(_user, authority.hYBNFT(), _tokenId, totalUsed);
    }

    /**
     * @notice Withdraw by BNB
     * @param _tokenId  YBNft token id
     */
    /// #if_succeeds {:msg "Withdraw failed"}  userInfos[_tokenId][msg.sender].amount == 0 && tokenInfos[_tokenId].totalStaked == old(tokenInfos[_tokenId]).totalStaked - old(userInfos[_tokenId][msg.sender]).amount;
    function withdraw(uint256 _tokenId) external nonReentrant onlyValidNFT(_tokenId) whenNotPaused {
        UserInfo memory userInfo = userInfos[_tokenId][msg.sender];
        TokenInfo storage tokenInfo = tokenInfos[_tokenId];

        // 1. claim reward from adapters
        _calcReward(_tokenId);

        // 2. withdraw funds from adapters
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        uint256 amountOut;
        uint256 beforeAmt = address(this).balance;
        for (uint8 i; i < adapterInfos.length; i++) {
            PendingWithdraw storage pendingWithdraw = pWithdrawals[_tokenId][adapterInfos[i].addr][msg.sender];

            uint256 tAmount = IAdapter(adapterInfos[i].addr).getUserAmount(_tokenId);
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(
                adapterInfos[i].addr
            );

            // when pool is unlocked
            if (!locked && pendingWithdraw.amount != 0) {
                amountOut += IAdapter(adapterInfos[i].addr).withdraw(
                    _tokenId,
                    (tAmount * pendingWithdraw.amount) / pendingWithdraw.totalStaked
                );

                pendingWithdraw.amount = 0;
                pendingWithdraw.addr = address(0);
                pendingWithdraw.totalStaked = 0;
            }

            // when pool is locked
            if (locked && pendingWithdraw.amount == 0) {
                pendingWithdraw.amount = userInfo.amount;
                pendingWithdraw.addr = adapterInfos[i].addr;
                pendingWithdraw.totalStaked = tokenInfo.totalStaked;
                continue;
            }

            // normal case
            if (userInfo.amount != 0)
                amountOut += IAdapter(adapterInfos[i].addr).withdraw(
                    _tokenId,
                    (tAmount * userInfo.amount) / tokenInfo.totalStaked
                );
        }
        require(amountOut == address(this).balance - beforeAmt, "Failed to withdraw");

        // 3. withdraw reward from investor
        _withdrawReward(_tokenId);

        // 4. update token info
        tokenInfo.totalStaked -= userInfo.amount;

        // 5. update adapter info in YBNFT
        IYBNFT(authority.hYBNFT()).updateInfo(IYBNFT.UpdateInfo(_tokenId, userInfo.amount, msg.sender, false));

        // 6. delete user info
        delete userInfos[_tokenId][msg.sender];

        // 7. withdraw funds
        if (amountOut != 0) {
            (bool success, ) = payable(msg.sender).call{value: amountOut}("");
            require(success, "Failed to withdraw");

            // 8. emit events
            emit Withdrawn(msg.sender, authority.hYBNFT(), _tokenId, amountOut);
        }
    }

    /**
     * @notice Claim
     * @param _tokenId  YBNft token id
     */
    /// #if_succeeds {:msg "Claim failed"}  userInfos[_tokenId][msg.sender].rewardDebt == 0;
    function claim(uint256 _tokenId) public nonReentrant whenNotPaused onlyValidNFT(_tokenId) {
        TokenInfo storage tokenInfo = tokenInfos[_tokenId];

        // 1. claim reward
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        uint256 pending = address(this).balance;
        for (uint8 i; i < adapterInfos.length; i++) {
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(
                adapterInfos[i].addr
            );

            if (!locked) IAdapter(adapterInfos[i].addr).claim(_tokenId);
        }
        pending = address(this).balance - pending;

        if (pending != 0) {
            // 2. update profit info in YBNFT
            IYBNFT(authority.hYBNFT()).updateProfitInfo(_tokenId, pending);

            if (tokenInfo.totalStaked != 0) tokenInfo.accRewardShare += (pending * 1e12) / tokenInfo.totalStaked;
        }

        // 3. withdraw reward from investor
        _withdrawReward(_tokenId);
    }

    /**
     * @notice pendingReward
     * @param _tokenId  YBNft token id
     * @param _account  user address
     */
    function pendingReward(
        uint256 _tokenId,
        address _account
    ) public view returns (uint256 amountOut, uint256 withdrawable) {
        UserInfo memory userInfo = userInfos[_tokenId][_account];
        TokenInfo memory tokenInfo = tokenInfos[_tokenId];

        if (!IYBNFT(authority.hYBNFT()).exists(_tokenId)) return (0, 0);

        // 1. get pending info from adapters
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        for (uint8 i; i < adapterInfos.length; i++) {
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(
                adapterInfos[i].addr
            );

            if (!locked) {
                (uint256 _amountOut, uint256 _withdrawable) = IAdapter(adapterInfos[i].addr).pendingReward(_tokenId);
                amountOut += _amountOut;
                withdrawable += _withdrawable;
            }
        }

        // 2. update accRewardShares
        uint256 updatedAccRewardShare1 = tokenInfo.accRewardShare;
        uint256 updatedAccRewardShare2 = tokenInfo.accRewardShare;
        if (tokenInfo.totalStaked != 0) {
            updatedAccRewardShare1 += (amountOut * 1e12) / tokenInfo.totalStaked;
            updatedAccRewardShare2 += (withdrawable * 1e12) / tokenInfo.totalStaked;
        }

        return (
            (userInfo.amount * (updatedAccRewardShare1 - userInfo.userShare)) / 1e12 + userInfo.rewardDebt,
            (userInfo.amount * (updatedAccRewardShare2 - userInfo.userShare)) / 1e12 + userInfo.rewardDebt
        );
    }

    /**
     * @notice Set treasury address
     * @param _treasury new treasury address
     */
    /// #if_succeeds {:msg "setTreasury failed"}  treasury == _treasury;
    function setTreasury(address _treasury) external onlyGovernor {
        require(_treasury != address(0), "Error: Invalid NFT address");

        treasury = _treasury;
        emit TreasuryUpdated(treasury);
    }

    /**
     * @notice Update funds for token id
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "updateFunds failed"}  tokenInfos[_tokenId].totalStaked == old(tokenInfos[_tokenId]).totalStaked;
    function updateFunds(uint256 _tokenId) external whenNotPaused onlyYBNft {
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        uint256 _amount = address(this).balance;
        for (uint8 i; i < adapterInfos.length; i++) {
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(
                adapterInfos[i].addr
            );

            IYBNFT.AdapterParam memory adapter = adapterInfos[i];
            if (!locked) IAdapter(adapter.addr).removeFunds(_tokenId);
        }
        _amount = address(this).balance - _amount;

        if (_amount == 0) return;

        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.AdapterParam memory adapter = adapterInfos[i];

            uint256 amountIn = (_amount * adapter.allocation) / 1e4;
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(adapter.addr);

            if (locked && amountIn != 0) revert("Error: Invalid alloc for locked");

            if (amountIn != 0) IAdapter(adapter.addr).updateFunds{value: amountIn}(_tokenId);
        }
    }

    /**
     * @notice internal function for calc reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "calcReward failed"}  userInfos[_tokenId][msg.sender].userShare == tokenInfos[_tokenId].accRewardShare;
    function _calcReward(uint256 _tokenId) internal {
        UserInfo storage userInfo = userInfos[_tokenId][msg.sender];
        TokenInfo storage tokenInfo = tokenInfos[_tokenId];

        // 1. claim reward from adapters
        uint256 pending = address(this).balance;
        _claim(_tokenId);
        pending = address(this).balance - pending;

        if (pending != 0) {
            // 2. update profit info in YBNFT
            IYBNFT(authority.hYBNFT()).updateProfitInfo(_tokenId, pending);

            // 3. update accRewardShare, rewardDebt values
            if (tokenInfo.totalStaked != 0) {
                tokenInfo.accRewardShare += (pending * 1e12) / tokenInfo.totalStaked;

                if (userInfo.amount != 0) {
                    userInfo.rewardDebt += (userInfo.amount * (tokenInfo.accRewardShare - userInfo.userShare)) / 1e12;
                }
            }
        }

        // 4. update userShare
        userInfo.userShare = tokenInfo.accRewardShare;
    }

    /**
     * @notice internal function for withdraw reward
     * @param _tokenId YBNFT token id
     */
    /// #if_succeeds {:msg "withdrawReward failed"}  userInfos[_tokenId][msg.sender].rewardDebt == 0 && userInfos[_tokenId][msg.sender].userShare == tokenInfos[_tokenId].accRewardShare;
    function _withdrawReward(uint256 _tokenId) internal {
        UserInfo storage userInfo = userInfos[_tokenId][msg.sender];
        TokenInfo memory tokenInfo = tokenInfos[_tokenId];

        // 1. calc reward amount stored in investor
        uint256 rewardAmt = (userInfo.amount * (tokenInfo.accRewardShare - userInfo.userShare)) /
            1e12 +
            userInfo.rewardDebt;

        // 2. update userInfo
        userInfo.rewardDebt = 0;
        userInfo.userShare = tokenInfo.accRewardShare;

        // 3. withdraw rewards
        if (rewardAmt != 0) {
            (bool success, ) = payable(msg.sender).call{value: rewardAmt}("");
            require(success, "Failed to withdraw reward");

            // 4. emit events
            emit Claimed(msg.sender, rewardAmt);
        }
    }

    /**
     * @notice internal function for claim
     * @param _tokenId  YBNft token id
     */
    function _claim(uint256 _tokenId) internal {
        IYBNFT.AdapterParam[] memory adapterInfos = IYBNFT(authority.hYBNFT()).getTokenAdapterParams(_tokenId);

        // claim rewards from adapters
        for (uint8 i; i < adapterInfos.length; i++) {
            bool locked = IHedgepieAdapterList(IHedgepieAuthority(authority).hAdapterList()).locked(
                adapterInfos[i].addr
            );

            if (!locked) IAdapter(adapterInfos[i].addr).claim(_tokenId);
        }
    }

    /**
     * @notice sgReceive from layerzero
     * @param _chainId stargate chain id
     * @param _srcAddress SRC address
     * @param _nonce nonce
     * @param _token recieve token
     * @param _amount token amount recieved
     * @param _payload payload
     */
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 _amount,
        bytes calldata _payload
    ) external payable override {
        (uint256 _tokenId, address _userAddress, address _router) = abi.decode(
            _payload[4:],
            (uint256, address, address)
        );

        // get function selector
        bytes4 fSig;
        fSig = fSig | _payload[3];
        fSig = (fSig >> 8) | _payload[2];
        fSig = (fSig >> 8) | _payload[1];
        fSig = (fSig >> 8) | _payload[0];

        // Swap receive token to ether
        address[] memory path = IPathFinder(IHedgepieAuthority(authority).pathFinder()).getPaths(
            _router,
            _token,
            HedgepieLibraryBsc.WBNB
        );

        // Approve token to swapRouter
        uint256 _bal = address(this).balance;
        IERC20(_token).approve(_router, 0);
        IERC20(_token).approve(_router, _amount);

        // Swap token to ether
        IPancakeRouter(_router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        _bal = address(this).balance - _bal;

        emit sgReceived(_chainId, _srcAddress, _nonce, _token, _amount, _payload);

        // Deposit onBehalf or Withdraw onBehalf
        (bool success, ) = address(this).call{value: _bal}(
            abi.encodeWithSignature("depositOnBehalf(uint256,address)", _tokenId, _userAddress)
        );
        require(success, "Failed to low call");
    }

    receive() external payable {}
}
