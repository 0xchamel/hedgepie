import hre from "hardhat";
import "@nomiclabs/hardhat-ethers";

async function deploy() {
    const HedgepieAdapterList = await hre.ethers.getContractFactory(
        "HedgepieAdapterList"
    );
    const HedgepieAuthority = await hre.ethers.getContractFactory(
        "HedgepieAuthority"
    );
    const Lib = await hre.ethers.getContractFactory("HedgepieLibraryBsc");
    const YBNFT = await hre.ethers.getContractFactory("YBNFT");
    const PathFinder = await hre.ethers.getContractFactory("PathFinder");

    // Deploy base contracts
    const authority = await HedgepieAuthority.deploy(
        "0xB34b18b191a2371359762429f9732F73af8ac211",
        "0xB34b18b191a2371359762429f9732F73af8ac211",
        "0xB34b18b191a2371359762429f9732F73af8ac211"
    );
    await authority.deployed();
    console.log("Authority: ", authority.address);

    const adapterList = await HedgepieAdapterList.deploy(authority.address);
    await adapterList.deployed();
    console.log("AdapterList: ", adapterList.address);

    const ybnft = await YBNFT.deploy(authority.address);
    await ybnft.deployed();
    console.log("YBNFT: ", ybnft.address);

    const pathFinder = await PathFinder.deploy(authority.address);
    await pathFinder.deployed();
    console.log("PathFinder: ", pathFinder.address);

    const lib = await Lib.deploy();
    await lib.deployed();
    console.log("LIB: ", lib.address);

    const HedgepieInvestor = await hre.ethers.getContractFactory(
        "HedgepieInvestor",
        {
            libraries: {
                HedgepieLibraryBsc:
                    "0x570aB366073bBA951Dc75788a991017cFe426c23",
            },
        }
    );
    const investor = await HedgepieInvestor.deploy("", "");
    await investor.deployed();
    console.log("Investor: ", investor.address);

    // Set base address to Authority
    await authority.setHInvestor(investor.address);
    await authority.setHYBNFT(ybnft.address);
    await authority.setHAdapterList(adapterList.address);
    await authority.setPathFinder(pathFinder.address);
}

async function main() {
    await deploy();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
