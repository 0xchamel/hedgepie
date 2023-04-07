import hre from "hardhat";
import { Logger } from "tslog";
import "@nomiclabs/hardhat-ethers";
import { deployUsingFactory } from "../utils";
import { lib, adapterNames, adapters } from "./constant";

const { setupBscAdapterWithLib } = require("../test/shared/setup");

async function deploy(name: string) {
    if (!adapters[name] || adapters[name].length === 0) {
        console.log("Adapter parameters are not existing.");
        return;
    }

    const Adapter = await setupBscAdapterWithLib(adapterNames[name], lib);
    for (let i = 0; i < adapters[name].length; i++) {
        await deployUsingFactory(Adapter, adapters[name][i]);
    }
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
