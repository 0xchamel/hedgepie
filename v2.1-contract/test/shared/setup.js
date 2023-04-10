const { ethers } = require("hardhat");

async function setupHedgepie(governor, pathManager, adapterManager, treasury) {
    const HedgepieAdapterList = await ethers.getContractFactory(
        "HedgepieAdapterList"
    );
    const HedgepieAuthority = await ethers.getContractFactory(
        "HedgepieAuthority"
    );

    const Lib = await ethers.getContractFactory("HedgepieLibraryBsc");
    const YBNFT = await ethers.getContractFactory("YBNFT");
    const PathFinder = await ethers.getContractFactory("PathFinder");

    // Deploy base contracts
    const authority = await HedgepieAuthority.deploy(
        governor.address,
        pathManager.address,
        adapterManager.address
    );
    await authority.deployed();

    const adapterList = await HedgepieAdapterList.deploy(authority.address);
    await adapterList.deployed();

    const ybnft = await YBNFT.deploy(authority.address);
    await ybnft.deployed();

    const pathFinder = await PathFinder.deploy(authority.address);
    await pathFinder.deployed();

    const lib = await Lib.deploy();
    await lib.deployed();

    const HedgepieInvestor = await ethers.getContractFactory(
        "HedgepieInvestor",
        {
            libraries: {
                HedgepieLibraryBsc: lib.address,
            },
        }
    );
    const investor = await HedgepieInvestor.deploy(
        treasury.address,
        authority.address
    );
    await investor.deployed();

    // Set base address to Authority
    await authority.connect(governor).setHInvestor(investor.address);
    await authority.connect(governor).setHYBNFT(ybnft.address);
    await authority.connect(governor).setHAdapterList(adapterList.address);
    await authority.connect(governor).setPathFinder(pathFinder.address);

    return [investor, authority, ybnft, adapterList, pathFinder, lib];
}

async function mintNFT(ybnft, adapters, stakingTokens, performanceFee) {
    // Mint NFTs
    let params = [];
    for (let i = 0; i < adapters.length; i++) {
        params.push([10000 / adapters.length, stakingTokens[i], adapters[i]]);
    }

    await ybnft.mint(params, performanceFee, "test tokenURI1");

    // tokenID: 2
    await ybnft.mint(params, performanceFee, "test tokenURI1");
}

async function setupBscAdapterWithLib(adapterName, lib) {
    const Adapter = await ethers.getContractFactory(adapterName, {
        libraries: {
            HedgepieLibraryBsc: lib.address,
        },
    });

    return Adapter;
}

module.exports = {
    mintNFT,
    setupHedgepie,
    setupBscAdapterWithLib,
};
