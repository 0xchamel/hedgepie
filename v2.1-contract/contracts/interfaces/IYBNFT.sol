// SPDX-License-Identifier: None
pragma solidity ^0.8.4;

interface IYBNFT {
    struct AdapterParam {
        uint256 allocation;
        address addr;
    }

    struct UpdateInfo {
        uint256 tokenId; // YBNFT tokenID
        uint256 value; // traded amount
        address account; // user address
        bool isDeposit; // deposit or withdraw
    }

    function exists(uint256) external view returns (bool);

    function getCurrentTokenId() external view returns (uint256);

    function performanceFee(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Get adapter parameters
     * @param tokenId  YBNft token id
     */
    function getTokenAdapterParams(uint256 tokenId) external view returns (AdapterParam[] memory);

    /**
     * @notice Mint nft
     * @param _adapterParams  parameters of adapters
     * @param _performanceFee  performance fee
     * @param _tokenURI  token URI
     */
    function mint(AdapterParam[] memory _adapterParams, uint256 _performanceFee, string memory _tokenURI) external;

    /**
     * @notice Update profit info
     * @param _tokenId  YBNFT tokenID
     * @param _value  amount of profit
     */
    function updateProfitInfo(uint256 _tokenId, uint256 _value) external;

    /**
     * @notice Update TVL, Profit, Participants info
     * @param param  update info param
     */
    function updateInfo(UpdateInfo memory param) external;
}
