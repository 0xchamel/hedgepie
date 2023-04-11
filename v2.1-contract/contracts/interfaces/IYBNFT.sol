// SPDX-License-Identifier: None
pragma solidity ^0.8.4;

interface IYBNFT {
    struct AdapterParam {
        uint256 allocation;
        address token;
        address addr;
    }

    struct UpdateInfo {
        uint256 tokenId;
        uint256 value;
        address account;
        bool flag;
    }

    function getCurrentTokenId() external view returns (uint256);

    function performanceFee(uint256 tokenId) external view returns (uint256);

    function getTokenAdapterParams(
        uint256 tokenId
    ) external view returns (AdapterParam[] memory);

    function exists(uint256) external view returns (bool);

    function mint(
        uint256[] calldata,
        address[] calldata,
        address[] calldata,
        uint256,
        string memory
    ) external;

    function updateProfitInfo(
        uint256 _tokenId,
        uint256 _value,
        bool _adding
    ) external;

    function updateInfo(UpdateInfo memory _param) external;
}
