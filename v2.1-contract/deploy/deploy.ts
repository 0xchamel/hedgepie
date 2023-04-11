import hre from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { verify } from "../utils";

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
        process.env.GOVERNOR || "",
        process.env.GOVERNOR || "",
        process.env.GOVERNOR || ""
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
                HedgepieLibraryBsc: lib.address,
            },
        }
    );
    const investor = await HedgepieInvestor.deploy(
        process.env.GOVERNOR || "",
        authority.address
    );
    await investor.deployed();
    console.log("Investor: ", investor.address);

    // Set base address to Authority
    await authority.setHInvestor(investor.address);
    await authority.setHYBNFT(ybnft.address);
    await authority.setHAdapterList(adapterList.address);
    await authority.setPathFinder(pathFinder.address);

    // verify base contracts
    await verify({
        contractName: "HedgepieAuthority",
        address: authority.address,
        constructorArguments: [
            process.env.GOVERNOR || "",
            process.env.GOVERNOR || "",
            process.env.GOVERNOR || "",
        ],
        contractPath: "contracts/base/HedgepieAuthority.sol:HedgepieAuthority",
    });
    await verify({
        contractName: "HedgepieAdapterList",
        address: adapterList.address,
        constructorArguments: [authority.address],
        contractPath:
            "contracts/base/HedgepieAdapterList.sol:HedgepieAdapterList",
    });
    await verify({
        contractName: "YBNFT",
        address: ybnft.address,
        constructorArguments: [authority.address],
        contractPath: "contracts/base/HedgepieYBNFT.sol:YBNFT",
    });
    await verify({
        contractName: "PathFinder",
        address: pathFinder.address,
        constructorArguments: [authority.address],
        contractPath: "contracts/base/PathFinder.sol:PathFinder",
    });
    await verify({
        contractName: "HedgepieInvestor",
        address: investor.address,
        constructorArguments: [process.env.GOVERNOR || "", authority.address],
        contractPath: "contracts/base/HedgepieInvestor.sol:HedgepieInvestor",
    });
    await verify({
        contractName: "HedgepieLibraryBsc",
        address: lib.address,
        constructorArguments: [],
        contractPath:
            "contracts/libraries/HedgepieLibraryBsc.sol:HedgepieLibraryBsc",
    });
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
