// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "../interfaces/IAdapterManager.sol";
import "../interfaces/IHedgepieInvestor.sol";
import "../interfaces/IFundToken.sol";
import "../interfaces/IYBNFT.sol";
import "../interfaces/IHedgepieAuthority.sol";

import "./HedgepieAccessControlled.sol";
import "./FundToken.sol";

contract YBNFT is ERC721, HedgepieAccessControlled {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct AdapterParam {
        uint256 allocation;
        address token;
        address addr;
    }

    struct AdapterDate {
        uint128 created;
        uint128 modified;
    }

    struct TokenInfo {
        uint256 tvl;
        uint256 participant;
        uint256 traded;
        uint256 profit;
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

    // tokenId => performanceFee
    mapping(uint256 => uint256) public performanceFee;

    // tokenId => fundToken
    mapping(uint256 => address) public fundTokens;

    // AdapterManager handler
    IAdapterManager public adapterManager;

    event Mint(address indexed minter, uint256 indexed tokenId);

    event FundTokenCreated(address indexed token, uint256 indexed tokenId);

    /**
     * @notice Construct
     * @param _hedgepieAuthority HedgepieAuthority address
     */
    constructor(address _hedgepieAuthority)
        ERC721("Hedgepie YBNFT", "YBNFT")
        HedgepieAccessControlled(IHedgepieAuthority(_hedgepieAuthority))
    {}

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
    function getTokenAdapterParams(uint256 _tokenId)
        public
        view
        returns (AdapterParam[] memory)
    {
        return adapterParams[_tokenId];
    }

    /**
     * @notice Get tokenURI from token id
     * @param _tokenId token id
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        return _tokenURIs[_tokenId];
    }

    /**
     * @notice Check if nft id is existed
     * @param _tokenId  YBNft token id
     */
    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    /**
     * @notice Mint nft with adapter infos
     * @param _adapterAllocations  allocation of adapters
     * @param _adapterTokens  token of adapters
     * @param _adapterAddrs  address of adapters
     */
    /// #if_succeeds {:msg "Mint failed"} adapterInfo[_tokenIdPointer._value].length == _adapterAllocations.length;
    function mint(
        uint256[] calldata _adapterAllocations,
        address[] calldata _adapterTokens,
        address[] calldata _adapterAddrs,
        uint256 _performanceFee,
        string memory _tokenURI
    ) external {
        require(
            _performanceFee < 1000,
            "Performance fee should be less than 10%"
        );
        require(
            _adapterTokens.length > 0 &&
                _adapterTokens.length == _adapterAllocations.length &&
                _adapterTokens.length == _adapterAddrs.length,
            "Mismatched adapters"
        );
        require(
            _checkPercent(_adapterAllocations),
            "Incorrect adapter allocation"
        );
        require(address(adapterManager) != address(0), "AdapterManger not set");

        for (uint256 i = 0; i < _adapterAddrs.length; i++) {
            (
                address adapterAddr,
                ,
                address stakingToken,
                bool status
            ) = IAdapterManager(adapterManager).getAdapterInfo(
                    _adapterAddrs[i]
                );
            require(
                _adapterAddrs[i] == adapterAddr,
                "Adapter address mismatch"
            );
            require(
                _adapterTokens[i] == stakingToken,
                "Staking token address mismatch"
            );
            require(status, "Adapter is inactive");
        }

        _tokenIdPointer.increment();
        performanceFee[_tokenIdPointer._value] = _performanceFee;

        _safeMint(msg.sender, _tokenIdPointer._value);
        _setTokenURI(_tokenIdPointer._value, _tokenURI);
        _setAdapterInfo(
            _tokenIdPointer._value,
            _adapterAllocations,
            _adapterTokens,
            _adapterAddrs
        );

        // deploy fund token here
        address token;
        bytes memory bytecode = type(FundToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_tokenIdPointer._value));
        assembly {
            token := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IFundToken(token).initialize(
            "YBNFT FundToken",
            string(
                abi.encodePacked(
                    "YFT_",
                    uint256(_tokenIdPointer._value).toString()
                )
            )
        );
        IFundToken(token).setMinter(
            IAdapterManager(adapterManager).investor(),
            true
        );
        fundTokens[_tokenIdPointer._value] = token;

        emit FundTokenCreated(token, _tokenIdPointer._value);

        emit Mint(msg.sender, _tokenIdPointer._value);
    }

    /**
     * @notice Update performance fee of adapters
     * @param _tokenId  tokenId of NFT
     * @param _performanceFee  address of adapters
     */
    function updatePerformanceFee(uint256 _tokenId, uint256 _performanceFee)
        external
    {
        require(
            _performanceFee < 1000,
            "Performance fee should be less than 10%"
        );
        require(msg.sender == ownerOf(_tokenId), "Invalid NFT Owner");

        performanceFee[_tokenId] = _performanceFee;
        adapterDate[_tokenId].modified = uint128(block.timestamp);
    }

    /**
     * @notice Update allocation of adapters
     * @param _tokenId  tokenId of NFT
     * @param _adapterAllocations  array of adapter allocation
     */
    function updateAllocations(
        uint256 _tokenId,
        uint256[] calldata _adapterAllocations
    ) external {
        require(
            _adapterAllocations.length == adapterParams[_tokenId].length,
            "Invalid allocation length"
        );
        require(msg.sender == ownerOf(_tokenId), "Invalid NFT Owner");
        require(
            _checkPercent(_adapterAllocations),
            "Incorrect adapter allocation"
        );

        for (uint256 i; i < adapterParams[_tokenId].length; i++) {
            adapterParams[_tokenId][i].allocation = _adapterAllocations[i];
        }

        adapterDate[_tokenId].modified = uint128(block.timestamp);

        // update funds
        require(
            IAdapterManager(adapterManager).investor() != address(0),
            "Invalid investor address"
        );
        IHedgepieInvestor(IAdapterManager(adapterManager).investor())
            .updateFunds(_tokenId);
    }

    /**
     * @notice Update token URI of NFT
     * @param _tokenId  tokenId of NFT
     * @param _tokenURI  URI of NFT
     */
    function updateTokenURI(uint256 _tokenId, string memory _tokenURI)
        external
    {
        require(msg.sender == ownerOf(_tokenId), "Invalid NFT Owner");

        _setTokenURI(_tokenId, _tokenURI);
        adapterDate[_tokenId].modified = uint128(block.timestamp);
    }

    /**
     * @notice Set token uri
     * @param _tokenId  token id
     * @param _tokenURI  token uri
     */
    function _setTokenURI(uint256 _tokenId, string memory _tokenURI)
        internal
        virtual
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );
        _tokenURIs[_tokenId] = _tokenURI;
    }

    /**
     * @notice Set adapter infos of nft from token id
     * @param _adapterAllocations  allocation of adapters
     * @param _adapterTokens  adapter token
     * @param _adapterAddrs  address of adapters
     */
    function _setAdapterInfo(
        uint256 _tokenId,
        uint256[] calldata _adapterAllocations,
        address[] calldata _adapterTokens,
        address[] calldata _adapterAddrs
    ) internal {
        for (uint256 i = 0; i < _adapterTokens.length; i++) {
            adapterParams[_tokenId].push(
                AdapterParam({
                    allocation: _adapterAllocations[i],
                    token: _adapterTokens[i],
                    addr: _adapterAddrs[i]
                })
            );
        }
        adapterDate[_tokenId] = AdapterDate({
            created: uint128(block.timestamp),
            modified: uint128(block.timestamp)
        });
    }

    /**
     * @notice Check if total percent of adapters is valid
     * @param _adapterAllocations  allocation of adapters
     */
    function _checkPercent(uint256[] calldata _adapterAllocations)
        internal
        pure
        returns (bool)
    {
        uint256 totalAlloc;
        for (uint256 i; i < _adapterAllocations.length; i++) {
            totalAlloc = totalAlloc + _adapterAllocations[i];
        }

        return totalAlloc <= 1e4;
    }
}
