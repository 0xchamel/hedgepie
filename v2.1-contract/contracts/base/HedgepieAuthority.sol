// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./HedgepieAccessControlled.sol";
import "../interfaces/IHedgepieAuthority.sol";

contract HedgepieAuthority is IHedgepieAuthority, HedgepieAccessControlled {
    /* ========== STATE VARIABLES ========== */

    address public override governor;

    address public override pathManager;

    address public override adapterManager;

    address public override hInvestor;

    address public override hYBNFT;

    address public override hAdapterList;

    address public override pathFinder;

    address public newGovernor;

    address public newPathManager;

    address public newAdapterManager;

    bool public override paused;

    /* ========== Constructor ========== */
    /**
     * @notice Constructor
     * @param _governor  address of Governor
     * @param _pathManager  address of path manager
     * @param _adapterManager  address of adapter manager
     */
    constructor(
        address _governor,
        address _pathManager,
        address _adapterManager
    ) HedgepieAccessControlled(IHedgepieAuthority(address(this))) {
        governor = _governor;
        emit GovernorPushed(address(0), governor, true);
        pathManager = _pathManager;
        emit PathManagerPushed(address(0), pathManager, true);
        adapterManager = _adapterManager;
        emit AdapterManagerPushed(address(0), adapterManager, true);
    }

    /* ========== GOV ONLY ========== */
    /**
     * @notice Push Governor
     * @param _newGovernor address of new governor
     * @param _effectiveImmediately  bool to set immediately or not
     */
    function pushGovernor(
        address _newGovernor,
        bool _effectiveImmediately
    ) external onlyGovernor {
        if (_effectiveImmediately) governor = _newGovernor;
        newGovernor = _newGovernor;
        emit GovernorPushed(governor, newGovernor, _effectiveImmediately);
    }

    /**
     * @notice Push path manager
     * @param _newPathManager address of new path manager
     * @param _effectiveImmediately  bool to set immediately or not
     */
    function pushPathManager(
        address _newPathManager,
        bool _effectiveImmediately
    ) external onlyGovernor {
        if (_effectiveImmediately) pathManager = _newPathManager;
        newPathManager = _newPathManager;
        emit PathManagerPushed(
            pathManager,
            newPathManager,
            _effectiveImmediately
        );
    }

    /**
     * @notice Push adapter manager
     * @param _newAdapterManager address of new adapter manager
     * @param _effectiveImmediately  bool to set immediately or not
     */
    function pushAdapterManager(
        address _newAdapterManager,
        bool _effectiveImmediately
    ) external onlyGovernor {
        if (_effectiveImmediately) adapterManager = _newAdapterManager;
        newAdapterManager = _newAdapterManager;
        emit AdapterManagerPushed(
            adapterManager,
            newAdapterManager,
            _effectiveImmediately
        );
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyGovernor {
        paused = true;
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyGovernor {
        paused = false;
    }

    /**
     * @notice Set Hedgepie Investor
     * @param _hInvestor address of HInvestor
     */
    function setHInvestor(address _hInvestor) external onlyGovernor {
        emit HInvestorUpdated(hInvestor, _hInvestor);
        hInvestor = _hInvestor;
    }

    /**
     * @notice Set YBNFT
     * @param _hYBNFT address of hedgepie YBNFT
     */
    function setHYBNFT(address _hYBNFT) external onlyGovernor {
        emit HYBNFTUpdated(hYBNFT, _hYBNFT);
        hYBNFT = _hYBNFT;
    }

    /**
     * @notice Set adapter list
     * @param _hAdapterList address of hedgepie adaper list
     */
    function setHAdapterList(address _hAdapterList) external onlyGovernor {
        emit HAdapterListUpdated(hAdapterList, _hAdapterList);
        hAdapterList = _hAdapterList;
    }

    /**
     * @notice Set path finder
     * @param _pathFinder address of hedgepie path finder
     */
    function setPathFinder(address _pathFinder) external onlyGovernor {
        emit PathFinderUpdated(pathFinder, _pathFinder);
        pathFinder = _pathFinder;
    }

    /* ========== PENDING ROLE ONLY ========== */
    /**
     * @notice Pull Governor
     */
    function pullGovernor() external {
        require(msg.sender == newGovernor, "!newGovernor");
        emit GovernorPulled(governor, newGovernor);
        governor = newGovernor;
    }

    /**
     * @notice Pull path manager
     */
    function pullPathManager() external {
        require(msg.sender == newPathManager, "!newPathManager");
        emit PathManagerPulled(pathManager, newPathManager);
        pathManager = newPathManager;
    }

    /**
     * @notice Pull adapter manager
     */
    function pullAdapterManager() external {
        require(msg.sender == newAdapterManager, "!newAdapterManager");
        emit AdapterManagerPulled(adapterManager, newAdapterManager);
        adapterManager = newAdapterManager;
    }
}
