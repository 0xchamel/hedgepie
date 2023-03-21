// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/HedgepieLibraryBsc.sol";
import "../interfaces/IYBNFT.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IFundToken.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

contract HedgepieInvestor is ReentrancyGuard, HedgepieAccessControlled {
    using SafeERC20 for IERC20;

    // ybnft address
    address public ybnft;

    // strategy manager
    address public adapterManager;

    // treasury address
    address public treasury;

    // adapter info
    address public adapterInfo;

    event Deposited(
        address indexed user,
        address nft,
        uint256 nftId,
        uint256 amount
    );
    event Withdrawn(
        address indexed user,
        address nft,
        uint256 nftId,
        uint256 amount
    );
    event Claimed(address indexed user, uint256 amount);
    event YieldWithdrawn(uint256 indexed nftId, uint256 amount);
    event AdapterManagerChanged(address indexed user, address adapterManager);
    event TreasuryChanged(address treasury);

    modifier onlyValidNFT(uint256 _tokenId) {
        require(
            IYBNFT(ybnft).exists(_tokenId),
            "Error: nft tokenId is invalid"
        );
        _;
    }

    /**
     * @notice Construct
     * @param _ybnft  address of YBNFT
     * @param _treasury  address of treasury
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(
        address _ybnft,
        address _treasury,
        address _hedgepieAuthority
    ) HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority)) {
        require(_ybnft != address(0), "Error: YBNFT address missing");
        require(_treasury != address(0), "Error: treasury address missing");

        ybnft = _ybnft;
        treasury = _treasury;
    }

    /**
     * @notice Deposit with BNB
     * @param _tokenId  YBNft token id
     */
    function deposit(uint256 _tokenId)
        external
        payable
        nonReentrant
        onlyValidNFT(_tokenId)
    {
        require(msg.value != 0, "Error: Insufficient BNB");

        IYBNFT.Adapter[] memory adapterInfos = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfos[i];

            uint256 amountIn = (msg.value * adapter.allocation) / 1e4;
            IAdapter(adapter.addr).deposit{value: amountIn}(_tokenId);
        }

        // mint fund token
        address fundToken = IYBNFT(ybnft).fundTokens(_tokenId);
        IFundToken(fundToken).mint(
            msg.sender,
            (msg.value * HedgepieLibraryBsc.getBNBPrice()) / 1e18
        );

        emit Deposited(msg.sender, ybnft, _tokenId, msg.value);
    }

    /**
     * @notice Withdraw by BNB
     * @param _tokenId  YBNft token id
     */
    function withdraw(uint256 _tokenId)
        external
        nonReentrant
        onlyValidNFT(_tokenId)
    {
        IYBNFT.Adapter[] memory adapterInfos = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 amountOut;
        for (uint8 i; i < adapterInfos.length; i++) {
            amountOut += IAdapter(adapterInfos[i].addr).withdraw(_tokenId, 0);
        }

        // burn fund token
        address fundToken = IYBNFT(ybnft).fundTokens(_tokenId);
        IFundToken(fundToken).burn(
            msg.sender,
            IERC20(fundToken).balanceOf(msg.sender)
        );

        emit Withdrawn(msg.sender, ybnft, _tokenId, amountOut);
    }

    /**
     * @notice Claim
     * @param _tokenId  YBNft token id
     */
    function claim(uint256 _tokenId)
        external
        nonReentrant
        onlyValidNFT(_tokenId)
    {
        IYBNFT.Adapter[] memory adapterInfos = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 amountOut;
        for (uint8 i; i < adapterInfos.length; i++) {
            amountOut += IAdapter(adapterInfos[i].addr).claim(_tokenId);
        }

        emit Claimed(msg.sender, amountOut);
        emit YieldWithdrawn(_tokenId, amountOut);
    }

    /**
     * @notice pendingReward
     * @param _tokenId  YBNft token id
     * @param _account  user address
     */
    function pendingReward(uint256 _tokenId, address _account)
        public
        view
        returns (uint256 amountOut, uint256 withdrawable)
    {
        if (!IYBNFT(ybnft).exists(_tokenId)) return (0, 0);

        IYBNFT.Adapter[] memory adapterInfos = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        for (uint8 i; i < adapterInfos.length; i++) {
            (uint256 _amountOut, uint256 _withdrawable) = IAdapter(
                adapterInfos[i].addr
            ).pendingReward(_tokenId);
            amountOut += _amountOut;
            withdrawable += _withdrawable;
        }
    }

    /**
     * @notice Set treasury address
     * @param _treasury new treasury address
     */
    function setTreasury(address _treasury) external onlyGovernor {
        require(_treasury != address(0), "Error: Invalid NFT address");

        treasury = _treasury;
        emit TreasuryChanged(treasury);
    }

    /**
     * @notice Update funds for token id
     * @param _tokenId YBNFT token id
     */
    function updateFunds(uint256 _tokenId) external {
        require(msg.sender == ybnft, "Error: YBNFT address mismatch");

        IYBNFT.Adapter[] memory adapterInfos = IYBNFT(ybnft).getAdapterInfo(
            _tokenId
        );

        uint256 _amount = address(this).balance;
        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfos[i];
            IAdapter(adapter.addr).removeFunds(_tokenId);
        }
        _amount = address(this).balance - _amount;

        if (_amount == 0) return;

        for (uint8 i; i < adapterInfos.length; i++) {
            IYBNFT.Adapter memory adapter = adapterInfos[i];

            uint256 amountIn = (_amount * adapter.allocation) / 1e4;
            if (amountIn != 0)
                IAdapter(adapter.addr).updateFunds{value: amountIn}(_tokenId);
        }
    }

    receive() external payable {}
}
