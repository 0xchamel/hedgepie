// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../type/BEP20.sol";

contract FundToken is BEP20 {
    // factory address
    address public factory;

    // token name
    string private _name;

    // token symbol
    string private _symbol;

    // mapping address => bool for minters
    mapping(address => bool) public minters;

    modifier onlyMinter() {
        require(minters[msg.sender], "FundToken: Invalid Minter");
        _;
    }

    constructor() BEP20("", "") {
        factory = msg.sender;
    }

    /**
     * @notice called once by the factory at time of deployment
     * @param name_ token name
     * @param symbol_ token symbol
     */
    function initialize(string memory name_, string memory symbol_) external {
        require(msg.sender == factory, "FundToken: Forbidden"); // sufficient check
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @notice override function of token name
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @notice override function of token symbol
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Moves `amount` of tokens from `from` to `to`.
     */
    function _transfer(
        address,
        address,
        uint256
    ) internal override {
        revert("FundToken: Transfer Disabled");
    }

    /**
     * @notice Set & Disable minter
     * @param _account address of minter
     * @param _isMinter boolean value for minter or not
     */
    function setMinter(address _account, bool _isMinter) external {
        require(
            msg.sender == factory && _account != address(0),
            "FundToken: Forbidden"
        );
        minters[_account] = _isMinter;
    }

    /**
     * @notice Mint token function
     * @param _account address that receives minted token
     * @param _amount amount of token
     */
    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    /**
     * @notice Burn token function
     * @param _account address that receives minted token
     * @param _amount amount of token
     */
    function burn(address _account, uint256 _amount) external onlyMinter {
        _burn(_account, _amount);
    }
}
