// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "../interfaces/IHedgepieAdapterList.sol";
import "../interfaces/IHedgepieInvestor.sol";
import "../interfaces/IYBNFT.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";

contract YBNFT is ERC721, HedgepieAccessControlled {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct AdapterParam {
        uint256 allocation; // allocation percent for adapter
        address addr; // adapter address
    }

    struct AdapterDate {
        uint128 created; // created time
        uint128 modified; // modified time
    }

    struct TokenInfo {
        uint256 tvl; // total tvl in usd
        uint256 participant; // total paticipants count
        uint256 traded; // total traded amount in usd
        uint256 profit; // total profit amount in usd
    }

    // current max tokenId
    Counters.Counter private _tokenIdPointer;

    // tokenId => token uri
    mapping(uint256 => string) private _tokenURIs;
    // tokenId => AdapterParam[]
    mapping(uint256 => AdapterParam[]) public adapterParams;
    // tokenId => AdapterDate
    mapping(uint256 => AdapterDate) public adapterDate;
    // tokenId => TokenInfo
    mapping(uint256 => TokenInfo) public tokenInfos;
    // nftId => participant's address existing
    mapping(uint256 => mapping(address => bool)) public participants;
    // tokenId => performanceFee
    mapping(uint256 => uint256) public performanceFee;

    /// @dev events
    event Mint(address indexed minter, uint256 indexed tokenId);
    event AdapterInfoUpdated(uint256 indexed tokenId, uint256 participant, uint256 traded, uint256 profit);

    modifier onlyNftOwner(uint256 tokenId) {
        require(msg.sender == ownerOf(tokenId), "Invalid NFT Owner");
        _;
    }

    /**
     * @notice Construct
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(
        address _hedgepieAuthority
    ) ERC721("Hedgepie YBNFT", "YBNFT") HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority)) {}

    /* ========== View ========== */
    /**
     * @notice Get current nft token id
     */
    function getCurrentTokenId() public view returns (uint256) {
        return _tokenIdPointer._value;
    }

    /**
     * @notice Get adapter parameters from nft tokenId
     * @param _tokenId  YBNft token id
     */
    function getTokenAdapterParams(uint256 _tokenId) public view returns (AdapterParam[] memory) {
        return adapterParams[_tokenId];
    }

    /**
     * @notice Get tokenURI from token id
     * @param _tokenId token id
     */
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return _tokenURIs[_tokenId];
    }

    /**
     * @notice Check if nft id is existed
     * @param _tokenId  YBNft token id
     */
    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    /* ========== General ========== */
    /**
     * @notice Mint nft with adapter infos
     * @param _adapterParams  parameters of adapters
     * @param _performanceFee  performance fee
     * @param _tokenURI  token URI
     */
    /// #if_succeeds {:msg "Mint failed"} getCurrentTokenId() == old(getCurrentTokenId()) + 1;
    function mint(AdapterParam[] memory _adapterParams, uint256 _performanceFee, string memory _tokenURI) external {
        require(_performanceFee < 1e3, "Fee should be less than 10%");
        require(_adapterParams.length != 0, "Mismatched adapters");
        require(address(authority.hAdapterList()) != address(0), "AdaterList not set");

        _checkPercent(_adapterParams);

        // check if adapters are listed and active
        _validate(_adapterParams);

        // increase nft token id
        _tokenIdPointer.increment();

        // update performance fee
        performanceFee[_tokenIdPointer._value] = _performanceFee;

        // mint NFT, set tokenURI and update adapter info
        _safeMint(msg.sender, _tokenIdPointer._value);
        _setTokenURI(_tokenIdPointer._value, _tokenURI);
        _setAdapterInfo(_tokenIdPointer._value, _adapterParams);

        emit Mint(msg.sender, _tokenIdPointer._value);
    }

    /* ========== NFT Onwer ONLY ========== */
    /**
     * @notice Update performance fee of adapters
     * @param _tokenId  tokenId of NFT
     * @param _performanceFee  address of adapters
     */
    /// #if_succeeds {:msg "updatePerformanceFee failed"}  performanceFee[_tokenId] == _performanceFee;
    function updatePerformanceFee(uint256 _tokenId, uint256 _performanceFee) external onlyNftOwner(_tokenId) {
        require(_performanceFee < 1e3, "Fee should be under 10%");

        performanceFee[_tokenId] = _performanceFee;
        _setModifiedDate(_tokenId);
    }

    /**
     * @notice Update allocation of adapters
     * @param _tokenId  tokenId of NFT
     * @param _adapterParams  parameters of adapters
     */
    function updateAllocations(uint256 _tokenId, AdapterParam[] memory _adapterParams) external onlyNftOwner(_tokenId) {
        require(_adapterParams.length >= adapterParams[_tokenId].length, "Invalid allocation length");
        require(authority.hInvestor() != address(0), "Invalid investor address");

        // update storage adapter allocation info
        _checkPercent(_adapterParams);
        _setAdapterInfo(_tokenId, _adapterParams);

        // update funds flow
        IHedgepieInvestor(authority.hInvestor()).updateFunds(_tokenId);
    }

    /**
     * @notice Update token URI of NFT
     * @param _tokenId  tokenId of NFT
     * @param _tokenURI  URI of NFT
     */
    function updateTokenURI(uint256 _tokenId, string memory _tokenURI) external onlyNftOwner(_tokenId) {
        _setTokenURI(_tokenId, _tokenURI);
        _setModifiedDate(_tokenId);
    }

    /* ========== Investor ONLY ========== */
    /**
     * @notice Update TVL, Profit, Participants info
     * @param param  update info param
     */
    /// #if_succeeds {:msg "updateInfo does not update the info"}  (old(tokenInfos[param.tokenId]).tvl + param.value == tokenInfos[param.tokenId].tvl || old(tokenInfos[param.tokenId]).tvl - param.value == tokenInfos[param.tokenId].tvl) && (old(tokenInfos[param.tokenId]).traded + param.value == tokenInfos[param.tokenId].traded);
    function updateInfo(IYBNFT.UpdateInfo memory param) external onlyInvestor {
        TokenInfo storage tokenInfo = tokenInfos[param.tokenId];

        // 1. update tvl info
        if (param.isDeposit) tokenInfo.tvl += param.value;
        else tokenInfo.tvl = tokenInfo.tvl < param.value ? 0 : tokenInfo.tvl - param.value;

        // 2. update traded info
        tokenInfo.traded += param.value;

        // 3. update participant info
        bool isExisted = participants[param.tokenId][param.account];

        if (param.isDeposit && !isExisted) {
            tokenInfo.participant++;
            participants[param.tokenId][param.account] = true;
        } else if (!param.isDeposit && isExisted) {
            tokenInfo.participant--;
            participants[param.tokenId][param.account] = false;
        }

        _emitEvent(param.tokenId);
    }

    /**
     * @notice Update profit info
     * @param _tokenId  YBNFT tokenID
     * @param _value  amount of profit
     */
    /// #if_succeeds {:msg "updateProfitInfo does not update the tokenInfos"}  old(tokenInfos[_tokenId]).profit + _value == tokenInfos[_tokenId].profit;
    function updateProfitInfo(uint256 _tokenId, uint256 _value) external onlyInvestor {
        tokenInfos[_tokenId].profit += _value;
        _emitEvent(_tokenId);
    }

    /* ========== Internal ========== */
    /**
     * @notice Set token uri
     * @param _tokenId  token id
     * @param _tokenURI  token uri
     */
    /// #if_succeeds {:msg "setTokenURI does not update the tokenURI"}  bytes(_tokenURIs[_tokenId]).length > 0;
    function _setTokenURI(uint256 _tokenId, string memory _tokenURI) internal virtual {
        require(_exists(_tokenId), "Nonexistent token");
        _tokenURIs[_tokenId] = _tokenURI;
    }

    /**
     * @notice Set adapter infos of nft from token id
     * @param _tokenId  token id
     * @param _adapterParams  adapter parameters
     */
    /// #if_succeeds {:msg "_setAdapterInfo does not update the adapterParams"}  old(adapterParams[_tokenId].length) + _adapterParams.length == adapterParams[_tokenId].length;
    function _setAdapterInfo(uint256 _tokenId, AdapterParam[] memory _adapterParams) internal {
        bool isExist = adapterParams[_tokenId].length != 0;
        if (!isExist) {
            for (uint256 i; i < _adapterParams.length; ) {
                adapterParams[_tokenId].push(
                    AdapterParam({allocation: _adapterParams[i].allocation, addr: _adapterParams[i].addr})
                );

                unchecked {
                    ++i;
                }
            }
            adapterDate[_tokenId] = AdapterDate({
                created: uint128(block.timestamp),
                modified: uint128(block.timestamp)
            });
        } else {
            uint256 curLen = adapterParams[_tokenId].length;
            for (uint256 i; i < _adapterParams.length; ) {
                if (i >= curLen) {
                    // validate adapter params
                    (address adapterAddr, , , bool status) = IHedgepieAdapterList(authority.hAdapterList())
                        .getAdapterInfo(_adapterParams[i].addr);
                    require(_adapterParams[i].addr == adapterAddr, "Adapter address mismatch");
                    require(status, "Adapter is inactive");

                    // push new adapter
                    adapterParams[_tokenId].push(
                        AdapterParam({allocation: _adapterParams[i].allocation, addr: _adapterParams[i].addr})
                    );
                } else {
                    adapterParams[_tokenId][i].allocation = _adapterParams[i].allocation;
                }

                unchecked {
                    ++i;
                }
            }

            _setModifiedDate(_tokenId);
        }
    }

    /**
     * @notice Check if total percent of adapters is valid
     * @param _adapterParams  parameters of adapters
     */
    function _checkPercent(AdapterParam[] memory _adapterParams) internal pure {
        uint256 totalAlloc;
        for (uint256 i; i < _adapterParams.length; i++) {
            totalAlloc = totalAlloc + _adapterParams[i].allocation;
        }

        require(totalAlloc == 1e4, "Incorrect adapter allocation");
    }

    /**
     * @notice Check if adpaterParams are valid
     * @param _adapterParams  parameters of adapters
     */
    function _validate(AdapterParam[] memory _adapterParams) internal {
        uint256 length = _adapterParams.length;
        for (uint256 i; i < length; ) {
            (address adapterAddr, , , bool status) = IHedgepieAdapterList(authority.hAdapterList()).getAdapterInfo(
                _adapterParams[i].addr
            );
            require(_adapterParams[i].addr == adapterAddr, "Adapter address mismatch");
            require(status, "Adapter is inactive");
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set Modified date for adapter
     * @param _tokenId  token id
     */
    /// #if_succeeds {:msg "_setModifiedDate does not update the adapterDate"}  adapterDate[_tokenId].modified == uint128(block.timestamp);
    function _setModifiedDate(uint256 _tokenId) internal {
        adapterDate[_tokenId].modified = uint128(block.timestamp);
    }

    /**
     * @notice Emit events for updated
     * @param _tokenId  token id
     */
    function _emitEvent(uint256 _tokenId) internal {
        emit AdapterInfoUpdated(
            _tokenId,
            tokenInfos[_tokenId].participant,
            tokenInfos[_tokenId].traded,
            tokenInfos[_tokenId].profit
        );
    }
}
