import "@nomiclabs/hardhat-ethers";
import fs from "fs";
import hre from "hardhat";
import * as path from "path";
import prodContracts from "../config/contracts.json";
import stgContracts from "../config/contracts_stg.json";

import { deployUsingFactory } from "../utils";
import { lib as prodLib, adapterNames, adapters as prodAdapters } from "./constant";
import { lib as stgLib, adapters as stgAdapters } from "./constant_stg";

const { setupBscAdapterWithLib } = require("../test/shared/setup");

async function deploy(name: string) {
    const isStaging = process.env.ENV && process.env.ENV === "STG";
    const contracts = isStaging ? stgContracts : prodContracts;
    const lib = isStaging ? stgLib : prodLib;
    const adapters = isStaging ? stgAdapters : prodAdapters;

    if (!adapters[name] || adapters[name].length === 0) {
        console.log("Adapter parameters are not existing.");
        return;
    }

    const Adapter = await setupBscAdapterWithLib(adapterNames[name], lib);
    let dAddrs = {};
    for (let i = 0; i < adapters[name].length; i++) {
        const res = await deployUsingFactory(Adapter, adapters[name][i], name);
        dAddrs[res.name] = res.address;
    }

    // update config file
    const configPath = path.join(__dirname, "../config", isStaging ? "contracts_stg.json" : "contracts.json");
    fs.writeFileSync(
        configPath,
        JSON.stringify({
            ...contracts,
            [name]: dAddrs,
        })
    );

    // add adapters to adapterList
    let params: string[] = [];
    Object.keys(dAddrs).forEach((key) => {
        params.push(dAddrs[key]);
    });
    const adapterList = await hre.ethers.getContractAt("HedgepieAdapterList", contracts.adapterList);
    await adapterList.addAdapters(params);
}

async function main() {
    // parameter should be from adapterNames keys
    await deploy("autofarm");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
