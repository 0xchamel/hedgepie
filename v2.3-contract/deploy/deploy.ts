import hre, { ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import fs from "fs";
import * as path from "path";

import { verify } from "../utils";
import { paths as prodPaths } from "./constant";
import { paths as stgPaths } from "./constant_stg";

async function deploy() {
    const isStaging = process.env.ENV && process.env.ENV === "STG";
    const paths = isStaging ? stgPaths : prodPaths;
    const HedgepieAdapterList = await hre.ethers.getContractFactory("HedgepieAdapterList");
    const HedgepieAuthority = await hre.ethers.getContractFactory("HedgepieAuthority");
    const Lib = await hre.ethers.getContractFactory("HedgepieLibraryBsc");
    const YBNFT = await hre.ethers.getContractFactory("YBNFT");
    const PathFinder = await hre.ethers.getContractFactory("PathFinder");

    // Deploy base contracts
    const authority = await HedgepieAuthority.deploy(
        process.env.GOVERNOR || "",
        process.env.PATH_MANAGER || "",
        process.env.ADAPTER_MANAGER || ""
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

    const HedgepieInvestor = await hre.ethers.getContractFactory("HedgepieInvestor", {
        libraries: {
            HedgepieLibraryBsc: lib.address,
        },
    });
    const investor = await HedgepieInvestor.deploy(process.env.TREASURY || "", authority.address);
    await investor.deployed();
    console.log("Investor: ", investor.address);

    // Set base address to Authority
    await authority.setHInvestor(investor.address);
    await authority.setHYBNFT(ybnft.address);
    await authority.setHAdapterList(adapterList.address);
    await authority.setPathFinder(pathFinder.address);

    // update config file
    const configPath = path.join(__dirname, "../config", isStaging ? "contracts_stg.json" : "contracts.json");
    fs.writeFileSync(
        configPath,
        JSON.stringify({
            lib: lib.address,
            authority: authority.address,
            investor: investor.address,
            pathFinder: pathFinder.address,
            ybnft: ybnft.address,
            adapterList: adapterList.address,
        })
    );

    // add paths to pathFinder
    for (let i = 0; i < paths.length; i++) {
        const path1 = [...paths[i]];
        path1.shift();
        let path2 = [...path1];

        if (path2 && path2?.length > 0) {
            const tmp = path2[0];
            path2[0] = path2[path2.length - 1];
            path2[path2.length - 1] = tmp;
        }

        // add router
        const isExist = await pathFinder.routers(paths[i][0]);
        if (!isExist) {
            const tx = await pathFinder.setRouter(paths[i][0], true);
            await tx.wait(5);
        }

        // add path
        await (await pathFinder.setPath(paths[i][0], paths[i][1], paths[i][paths[i].length - 1], [...path1])).wait(5);
        await (await pathFinder.setPath(paths[i][0], paths[i][paths[i].length - 1], paths[i][1], [...path2])).wait(5);
    }

    // verify base contracts
    await verify({
        contractName: "HedgepieAuthority",
        address: authority.address,
        constructorArguments: [
            process.env.GOVERNOR || "",
            process.env.PATH_MANAGER || "",
            process.env.ADAPTER_MANAGER || "",
        ],
        contractPath: "contracts/base/HedgepieAuthority.sol:HedgepieAuthority",
    });
    await verify({
        contractName: "HedgepieAdapterList",
        address: adapterList.address,
        constructorArguments: [authority.address],
        contractPath: "contracts/base/HedgepieAdapterList.sol:HedgepieAdapterList",
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
        constructorArguments: [process.env.TREASURY || "", authority.address],
        contractPath: "contracts/base/HedgepieInvestor.sol:HedgepieInvestor",
    });
    await verify({
        contractName: "HedgepieLibraryBsc",
        address: lib.address,
        constructorArguments: [],
        contractPath: "contracts/libraries/HedgepieLibraryBsc.sol:HedgepieLibraryBsc",
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
