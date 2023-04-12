import "@nomiclabs/hardhat-ethers";
import fs from "fs";
import * as path from "path";
import contracts from "../config/contracts.json";

import { deployUsingFactory } from "../utils";
import { lib, adapterNames, adapters } from "./constant";

const { setupBscAdapterWithLib } = require("../test/shared/setup");

async function deploy(name: string) {
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
    const configPath = path.join(__dirname, "../config", "contracts.json");
    fs.writeFileSync(
        configPath,
        JSON.stringify({
            ...contracts,
            [name]: dAddrs,
        })
    );
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
