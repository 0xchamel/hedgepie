// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libraries/HedgepieLibraryMatic.sol";

contract HedgepieInvestorMatic is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeBEP20 for IBEP20;

    struct UserAdapterInfo {
        uint256 amount;
        uint256 userShares;
        uint256 userShares1;
    }

    struct AdapterInfo {
        uint256 accTokenPerShare;
        uint256 accTokenPerShare1;
        uint256 totalStaked;
    }

    struct NFTInfo {
        uint256 tvl;
        uint256 totalParticipant;
    }

    // ybnft => nft id => NFTInfo
    mapping(address => mapping(uint256 => NFTInfo)) public nftInfo;

    // user => ybnft => nft id => amount(Invested WMATIC)
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public userInfo;

    // user => nft id => adapter => UserAdapterInfo
    mapping(address => mapping(uint256 => mapping(address => UserAdapterInfo)))
        public userAdapterInfos;

    // nft id => adapter => AdapterInfo
    mapping(uint256 => mapping(address => AdapterInfo)) public adapterInfos;

    // ybnft address
    address public ybnft;

    // swap router address
    address public swapRouter;

    // wrapped matic address
    address public wmatic;

    // strategy manager
    address public adapterManager;

    address public treasuryAddr;

    event DepositMATIC(
        address indexed user,
        address nft,
        uint256 nftId,
        uint256 amount
    );
    event WithdrawMATIC(
        address indexed user,
        address nft,
        uint256 nftId,
        uint256 amount
    );
    event Claimed(address indexed user, uint256 amount);
    event AdapterManagerChanged(address indexed user, address adapterManager);

    /**
     * @notice Construct
     * @param _ybnft  address of YBNFT
     * @param _swapRouter  address of pancakeswap router
     * @param _wmatic  address of Wrapped MATIC address
     */
    constructor(
        address _ybnft,
        address _swapRouter,
        address _wmatic
    ) {
        require(_ybnft != address(0), "YBNFT address missing");
        require(_swapRouter != address(0), "swap router missing");
        require(_wmatic != address(0), "wmatic missing");

        ybnft = _ybnft;
        swapRouter = _swapRouter;
        wmatic = _wmatic;
    }

    /**
     * @notice Set treasury address and percent
     * @param _treasury  treasury address
     */
    /// #if_succeeds {:msg "Treasury not updated"} treasuryAddr == _treasury;
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasuryAddr = _treasury;
    }

    /**
     * @notice Deposit with MATIC
     * @param _user  user address
     * @param _tokenId  YBNft token id
     * @param _amount  MATIC amount
     */
    /// #if_succeeds {:msg "userInfo not increased"} userInfo[_user][ybnft][_tokenId] > old(userInfo[_user][ybnft][_tokenId]);
    function depositMATIC(
        address _user,
        uint256 _tokenId,
        uint256 _amount
    ) external payable nonReentrant {
        require(_amount != 0, "Amount can not be 0");
        require(msg.value == _amount, "Insufficient MATIC");
        require(IYBNFT(ybnft).exists(_tokenId), "nft tokenId is invalid");

        IYBNFT.Adapter[] memory adapterInfo = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256[2] memory balances;
        balances[0] = address(this).balance;

        for (uint8 i = 0; i < adapterInfo.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfo[i];

            uint256 amountIn = (_amount * adapter.allocation) / 1e4;
            uint256 amountOut;
            if (IAdapterMatic(adapter.addr).router() == address(0)) {
                if (adapter.token == wmatic) {
                    amountOut = amountIn;
                } else {
                    // swap
                    amountOut = HedgepieLibraryMatic.swapOnRouter(
                        adapter.addr,
                        amountIn,
                        IAdapterMatic(adapter.addr).lpStakingToken() == address(0)
                            ? adapter.token
                            : IAdapterMatic(adapter.addr).lpStakingToken(),
                        swapRouter,
                        wmatic
                    );
                }
            } else if (IAdapterMatic(adapter.addr).liquidityToken() != address(0)) {
                amountOut = HedgepieLibraryMatic.getLPLiquidity(
                    adapter.addr,
                    adapter.token,
                    amountIn,
                    adapterManager,
                    swapRouter,
                    wmatic
                );
            } else {
                // get lp
                amountOut = HedgepieLibraryMatic.getLP(
                    adapter,
                    wmatic,
                    msg.sender,
                    amountIn,
                    _tokenId
                );
            }

            if (IAdapterMatic(adapter.addr).noDeposit()) {
                IAdapterMatic(adapter.addr).increaseWithdrawalAmount(
                    msg.sender,
                    _tokenId,
                    amountOut
                );
            } else {
                // deposit to adapter
                UserAdapterInfo storage _userAdapterInfo = userAdapterInfos[
                    msg.sender
                ][_tokenId][adapter.addr];

                AdapterInfo storage _adapterInfo = adapterInfos[_tokenId][
                    adapter.addr
                ];

                // Get stargate LP token
                if (IAdapterMatic(adapter.addr).lpStakingToken() != address(0)) {
                    IBEP20(IAdapterMatic(adapter.addr).lpStakingToken()).approve(
                        IAdapterMatic(adapter.addr).lpProvider(),
                        amountOut
                    );

                    (address to, , bytes memory data) = IAdapterMatic(adapter.addr)
                        .getLPCallData(amountOut);

                    amountOut = IBEP20(adapter.token).balanceOf(address(this));
                    (bool success, ) = to.call{value: 0}(data);

                    amountOut =
                        IBEP20(adapter.token).balanceOf(address(this)) -
                        amountOut;
                    require(success && amountOut != 0, "Failed to get LP");
                }

                // deposit to adapter
                HedgepieLibraryMatic.depositToAdapter(
                    adapterManager,
                    msg.sender,
                    _tokenId,
                    amountOut,
                    adapter,
                    _userAdapterInfo,
                    _adapterInfo
                );
            }

            userAdapterInfos[_user][_tokenId][adapter.addr].amount += amountOut;
            adapterInfos[_tokenId][adapter.addr].totalStaked += amountOut;
        }

        nftInfo[ybnft][_tokenId].tvl += _amount;
        if (userInfo[_user][ybnft][_tokenId] == 0) {
            nftInfo[ybnft][_tokenId].totalParticipant++;
        }
        userInfo[_user][ybnft][_tokenId] += _amount;

        balances[1] = address(this).balance;
        if (balances[1] > balances[0]) {
            (bool success, ) = payable(_user).call{
                value: balances[1] - balances[0]
            }("");
            require(success, "Failed to send remained MATIC");
        }

        emit DepositMATIC(_user, ybnft, _tokenId, _amount);
    }

    /**
     * @notice Withdraw by MATIC
     * @param _user  user address
     * @param _tokenId  YBNft token id
     */
    /// #if_succeeds {:msg "userInfo not decreased"} userInfo[_user][ybnft][_tokenId] < old(userInfo[_user][ybnft][_tokenId]);
    function withdrawMATIC(address _user, uint256 _tokenId)
        external
        nonReentrant
    {
        require(IYBNFT(ybnft).exists(_tokenId), "nft tokenId is invalid");
        uint256 userAmount = userInfo[_user][ybnft][_tokenId];
        require(userAmount != 0, "Amount should be greater than 0");

        IYBNFT.Adapter[] memory adapterInfo = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 amountOut;
        uint256[3] memory balances;

        for (uint8 i = 0; i < adapterInfo.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfo[i];
            UserAdapterInfo storage userAdapter = userAdapterInfos[msg.sender][
                _tokenId
            ][adapter.addr];

            if (IAdapterMatic(adapter.addr).noDeposit()) {
                balances[2] = IAdapterMatic(adapter.addr).getWithdrawalAmount(
                    msg.sender,
                    _tokenId
                );
                IAdapterMatic(adapter.addr).setWithdrawalAmount(
                    msg.sender,
                    _tokenId,
                    0
                );
            } else {
                balances[0] = adapter.token == wmatic
                    ? address(this).balance
                    : IBEP20(adapter.token).balanceOf(address(this));

                _withdrawFromAdapter(
                    adapter.addr,
                    _tokenId,
                    IAdapterMatic(adapter.addr).getWithdrawalAmount(
                        msg.sender,
                        _tokenId
                    )
                );

                balances[1] = adapter.token == wmatic
                    ? address(this).balance
                    : IBEP20(adapter.token).balanceOf(address(this));

                unchecked {
                    balances[2] = balances[1] - balances[0];
                }
            }

            if (IAdapterMatic(adapter.addr).router() == address(0)) {
                if (adapter.token == wmatic) {
                    unchecked {
                        amountOut += balances[2];
                    }
                } else {
                    if (IAdapterMatic(adapter.addr).lpStakingToken() != address(0)) {
                        IBEP20(adapter.token).approve(
                            IAdapterMatic(adapter.addr).lpProvider(),
                            balances[1] - balances[0]
                        );

                        (address to, , bytes memory data) = IAdapterMatic(
                            adapter.addr
                        ).removeLPCallData(balances[1] - balances[0]);

                        balances[0] = IBEP20(
                            IAdapterMatic(adapter.addr).lpStakingToken()
                        ).balanceOf(address(this));

                        (bool success, ) = to.call{value: 0}(data);

                        balances[1] = IBEP20(
                            IAdapterMatic(adapter.addr).lpStakingToken()
                        ).balanceOf(address(this));

                        require(
                            success && balances[1] > balances[0],
                            "Failed to remove LP"
                        );
                    }

                    // swap
                    amountOut += HedgepieLibraryMatic.swapforMatic(
                        adapter.addr,
                        balances[2],
                        IAdapterMatic(adapter.addr).lpStakingToken() == address(0)
                            ? adapter.token
                            : IAdapterMatic(adapter.addr).lpStakingToken(),
                        swapRouter,
                        wmatic
                    );
                }
            } else if (IAdapterMatic(adapter.addr).liquidityToken() != address(0)) {
                amountOut += HedgepieLibraryMatic.withdrawLPLiquidity(
                    adapter.addr,
                    adapter.token,
                    balances[2],
                    adapterManager,
                    swapRouter,
                    wmatic
                );
            } else {
                uint256 taxAmount;
                amountOut += HedgepieLibraryMatic.withdrawLP(
                    adapter,
                    wmatic,
                    msg.sender,
                    balances[2],
                    _tokenId
                );

                if (IAdapterMatic(adapter.addr).rewardToken() != address(0)) {
                    // Convert rewards to MATIC
                    uint256[2] memory rewards;
                    (rewards[0], rewards[1]) = HedgepieLibraryMatic
                        .getRewards(
                            adapterInfos[_tokenId][adapter.addr],
                            userAdapterInfos[msg.sender][_tokenId][
                                adapter.addr
                            ],
                            adapter.addr
                        );
                    if (
                        rewards[0] >
                        IBEP20(IAdapterMatic(adapter.addr).rewardToken()).balanceOf(
                            address(this)
                        )
                    )
                        rewards[0] = IBEP20(
                            IAdapterMatic(adapter.addr).rewardToken()
                        ).balanceOf(address(this));

                    userAdapter.userShares = 0;

                    taxAmount =
                        (rewards[0] * IYBNFT(ybnft).performanceFee(_tokenId)) /
                        1e4;

                    if (taxAmount != 0) {
                        IBEP20(IAdapterMatic(adapter.addr).rewardToken()).transfer(
                            treasuryAddr,
                            taxAmount
                        );
                    }

                    if (rewards[0] != 0) {
                        amountOut += HedgepieLibraryMatic.swapforMatic(
                            adapter.addr,
                            rewards[0] - taxAmount,
                            IAdapterMatic(adapter.addr).rewardToken(),
                            swapRouter,
                            wmatic
                        );
                    }

                    if (rewards[1] != 0) {
                        userAdapter.userShares1 = 0;

                        taxAmount =
                            (rewards[1] *
                                IYBNFT(ybnft).performanceFee(_tokenId)) /
                            1e4;

                        if (taxAmount != 0) {
                            IBEP20(IAdapterMatic(adapter.addr).rewardToken1())
                                .transfer(treasuryAddr, taxAmount);
                        }

                        amountOut += HedgepieLibraryMatic.swapforMatic(
                            adapter.addr,
                            rewards[1] - taxAmount,
                            IAdapterMatic(adapter.addr).rewardToken1(),
                            swapRouter,
                            wmatic
                        );
                    }
                }
            }

            adapterInfos[_tokenId][adapter.addr]
                .totalStaked -= userAdapterInfos[_user][_tokenId][adapter.addr]
                .amount;
            userAdapterInfos[_user][_tokenId][adapter.addr].amount = 0;
        }

        if (nftInfo[ybnft][_tokenId].tvl < userAmount)
            nftInfo[ybnft][_tokenId].tvl = 0;
        else nftInfo[ybnft][_tokenId].tvl -= userAmount;

        if (nftInfo[ybnft][_tokenId].totalParticipant > 0)
            nftInfo[ybnft][_tokenId].totalParticipant--;

        userInfo[_user][ybnft][_tokenId] -= userAmount;

        if (amountOut != 0) {
            (bool success, ) = payable(_user).call{value: amountOut}("");
            require(success, "Failed to send MATIC");
        }
        emit WithdrawMATIC(_user, ybnft, _tokenId, userAmount);
    }

    /**
     * @notice Claim
     * @param _tokenId  YBNft token id
     */
    function claim(uint256 _tokenId) external nonReentrant {
        require(IYBNFT(ybnft).exists(_tokenId), "nft tokenId is invalid");
        uint256 userAmount = userInfo[msg.sender][ybnft][_tokenId];
        require(userAmount != 0, "Amount should be greater than 0");

        IYBNFT.Adapter[] memory adapterInfo = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 amountOut;
        uint256[2] memory rewards;
        for (uint8 i = 0; i < adapterInfo.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfo[i];
            UserAdapterInfo storage userAdapter = userAdapterInfos[msg.sender][
                _tokenId
            ][adapter.addr];

            (rewards[0], rewards[1]) = HedgepieLibraryMatic.getRewards(
                adapterInfos[_tokenId][adapter.addr],
                userAdapterInfos[msg.sender][_tokenId][adapter.addr],
                adapter.addr
            );
            userAdapter.userShares = adapterInfos[_tokenId][adapter.addr]
                .accTokenPerShare;
            userAdapter.userShares1 = adapterInfos[_tokenId][adapter.addr]
                .accTokenPerShare1;

            if (
                rewards[0] != 0 &&
                IAdapterMatic(adapter.addr).rewardToken() != address(0)
            ) {
                amountOut += HedgepieLibraryMatic.swapforMatic(
                    adapter.addr,
                    rewards[0],
                    IAdapterMatic(adapter.addr).rewardToken(),
                    swapRouter,
                    wmatic
                );
            }

            if (
                rewards[1] != 0 &&
                IAdapterMatic(adapter.addr).rewardToken1() != address(0)
            ) {
                amountOut += HedgepieLibraryMatic.swapforMatic(
                    adapter.addr,
                    rewards[1],
                    IAdapterMatic(adapter.addr).rewardToken1(),
                    swapRouter,
                    wmatic
                );
            }
        }

        if (amountOut != 0) {
            uint256 taxAmount = (amountOut *
                IYBNFT(ybnft).performanceFee(_tokenId)) / 1e4;
            (bool success, ) = payable(treasuryAddr).call{value: taxAmount}("");
            require(success, "Failed to send MATIC to Treasury");

            (success, ) = payable(msg.sender).call{
                value: amountOut - taxAmount
            }("");
            require(success, "Failed to send MATIC");
            emit Claimed(msg.sender, amountOut);
        }
    }

    /**
     * @notice Set strategy manager contract
     * @param _adapterManager  nft address
     */
    /// #if_succeeds {:msg "Adapter manager not set"} adapterManager == _adapterManager;
    function setAdapterManager(address _adapterManager) external onlyOwner {
        require(_adapterManager != address(0), "Invalid NFT address");

        adapterManager = _adapterManager;

        emit AdapterManagerChanged(msg.sender, _adapterManager);
    }

    /**
     * @notice Withdraw fund from adapter
     * @param _adapterAddr  adapter address
     * @param _amount  token amount
     */
    function _withdrawFromAdapter(
        address _adapterAddr,
        uint256 _tokenId,
        uint256 _amount
    ) internal {
        uint256[4] memory rewardTokenAmount;
        address[3] memory tokens;
        tokens[0] = IAdapterMatic(_adapterAddr).stakingToken();
        tokens[1] = IAdapterMatic(_adapterAddr).rewardToken();
        tokens[2] = IAdapterMatic(_adapterAddr).rewardToken1();

        rewardTokenAmount[0] = tokens[1] != address(0)
            ? IBEP20(tokens[1]).balanceOf(address(this))
            : 0;
        rewardTokenAmount[2] = tokens[2] != address(0)
            ? IBEP20(tokens[2]).balanceOf(address(this))
            : 0;

        (
            address to,
            uint256 value,
            bytes memory callData
        ) = IAdapterManagerMatic(adapterManager).getWithdrawCallData(
                _adapterAddr,
                _amount
            );

        (bool success, ) = to.call{value: value}(callData);
        require(success, "Withdraw internal issue");

        if (IAdapterMatic(_adapterAddr).isReward()) {
            (to, value, callData) = IAdapterManagerMatic(adapterManager)
                .getRewardCallData(_adapterAddr);

            (success, ) = to.call{value: value}(callData);
            require(success, "getReward internal issue");
        }

        rewardTokenAmount[1] = tokens[1] != address(0)
            ? IBEP20(tokens[1]).balanceOf(address(this))
            : 0;
        rewardTokenAmount[3] = tokens[2] != address(0)
            ? IBEP20(tokens[2]).balanceOf(address(this))
            : 0;

        if (tokens[1] == tokens[0]) rewardTokenAmount[1] += _amount;
        if (tokens[2] == tokens[0]) rewardTokenAmount[3] += _amount;
        if (tokens[1] != address(0) && tokens[1] != tokens[0]) {
            AdapterInfo storage adapter = adapterInfos[_tokenId][_adapterAddr];

            if (
                rewardTokenAmount[1] - rewardTokenAmount[0] != 0 &&
                adapter.accTokenPerShare != 0
            ) {
                adapter.accTokenPerShare +=
                    ((rewardTokenAmount[1] - rewardTokenAmount[0]) * 1e12) /
                    adapter.totalStaked;
            }

            if (
                tokens[2] != address(0) &&
                rewardTokenAmount[3] - rewardTokenAmount[2] != 0
            ) {
                adapter.accTokenPerShare1 +=
                    ((rewardTokenAmount[3] - rewardTokenAmount[2]) * 1e12) /
                    adapter.totalStaked;
            }
        }

        // update storage data on adapter
        IAdapterMatic(_adapterAddr).setWithdrawalAmount(msg.sender, _tokenId, 0);
    }

    /**
     * @notice Get current rewards amount in MATIC
     * @param _account user account address
     * @param _tokenId NFT token id
     */
    function pendingReward(address _account, uint256 _tokenId)
        public
        view
        returns (uint256)
    {
        IYBNFT.Adapter[] memory ybnftAapters = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 rewards;

        for (uint8 i = 0; i < ybnftAapters.length; i++) {
            IYBNFT.Adapter memory adapter = ybnftAapters[i];
            UserAdapterInfo memory userAdapter = userAdapterInfos[_account][
                _tokenId
            ][adapter.addr];
            AdapterInfo memory adapterInfo = adapterInfos[_tokenId][
                adapter.addr
            ];

            address rewardToken = IAdapterMatic(adapter.addr).rewardToken();
            if (
                rewardToken != address(0) &&
                adapterInfo.totalStaked != 0 &&
                adapterInfo.accTokenPerShare != 0
            ) {
                uint256 updatedAccTokenPerShare = adapterInfo.accTokenPerShare +
                    ((IAdapterMatic(adapter.addr).pendingReward() * 1e12) /
                        adapterInfo.totalStaked);

                uint256 tokenRewards = ((updatedAccTokenPerShare -
                    userAdapter.userShares) * userAdapter.amount) / 1e12;

                if (tokenRewards != 0)
                    rewards += rewardToken == wmatic
                        ? tokenRewards
                        : IPancakeRouter(swapRouter).getAmountsOut(
                            tokenRewards,
                            HedgepieLibraryMatic.getPaths(
                                adapter.addr,
                                rewardToken,
                                wmatic
                            )
                        )[1];

                address rewardToken1 = IAdapterMatic(adapter.addr).rewardToken1();
                if (rewardToken1 != address(0)) {
                    updatedAccTokenPerShare =
                        adapterInfo.accTokenPerShare1 +
                        ((IAdapterMatic(adapter.addr).pendingReward1() * 1e12) /
                            adapterInfo.totalStaked);

                    tokenRewards =
                        ((updatedAccTokenPerShare - userAdapter.userShares1) *
                            userAdapter.amount) /
                        1e12;

                    if (tokenRewards != 0)
                        rewards += rewardToken1 == wmatic
                            ? tokenRewards
                            : IPancakeRouter(swapRouter).getAmountsOut(
                                tokenRewards,
                                HedgepieLibraryMatic.getPaths(
                                    adapter.addr,
                                    rewardToken1,
                                    wmatic
                                )
                            )[1];
                }
            } else if (IAdapterMatic(adapter.addr).isVault()) {
                uint256 updatedAccTokenPerShare = ((IAdapterMatic(adapter.addr)
                    .pendingReward() * 1e12) / adapterInfo.totalStaked);

                uint256 tokenRewards = ((updatedAccTokenPerShare -
                    userAdapter.userShares) * userAdapter.amount) / 1e12;

                if (IAdapterMatic(adapter.addr).router() == address(0)) {
                    rewards += tokenRewards == 0
                        ? 0
                        : IPancakeRouter(swapRouter).getAmountsOut(
                            tokenRewards,
                            HedgepieLibraryMatic.getPaths(
                                adapter.addr,
                                IAdapterMatic(adapter.addr).rewardToken(),
                                wmatic
                            )
                        )[1];
                } else {
                    address pairToken = IAdapterMatic(adapter.addr).stakingToken();
                    address[2] memory tokens;
                    tokens[0] = IPancakePair(pairToken).token0();
                    tokens[1] = IPancakePair(pairToken).token1();
                    (uint112 reserve0, uint112 reserve1, ) = IPancakePair(
                        pairToken
                    ).getReserves();

                    uint256[2] memory amounts;
                    amounts[0] =
                        (reserve0 * tokenRewards) /
                        IPancakePair(pairToken).totalSupply();
                    amounts[1] =
                        (reserve1 * tokenRewards) /
                        IPancakePair(pairToken).totalSupply();

                    if (tokens[0] == wmatic) rewards += amounts[0];
                    else
                        rewards += IPancakeRouter(swapRouter).getAmountsOut(
                            amounts[0],
                            HedgepieLibraryMatic.getPaths(
                                adapter.addr,
                                tokens[0],
                                wmatic
                            )
                        )[1];

                    if (tokens[1] == wmatic) rewards += amounts[1];
                    else
                        rewards += IPancakeRouter(swapRouter).getAmountsOut(
                            amounts[1],
                            HedgepieLibraryMatic.getPaths(
                                adapter.addr,
                                tokens[1],
                                wmatic
                            )
                        )[1];
                }
            }
        }

        return rewards;
    }

    receive() external payable {}

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
