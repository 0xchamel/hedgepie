import hre from "hardhat";
import { Logger } from "tslog";
import { wait } from "../utils/time";
import { adapterPaths } from "../deploy/constant";

const log: Logger = new Logger();

async function verify({
    contractName,
    address,
    constructorArguments,
    contractPath,
}: {
    contractName: string;
    address: string;
    constructorArguments: any[];
    contractPath: string;
}) {
    wait(10000);

    log.info(`Verifying "${contractName}" on network: ${hre.network.name}, address: ${address}`);
    try {
        await hre.run("verify:verify", {
            address,
            constructorArguments,
            contract: contractPath,
        });
        log.info(`Verifying "${contractName}" on network: ${hre.network.name}, address: ${address} was succeeded.`);
    } catch (e) {
        log.error(`Verification error: ${e}`);
    }
}

const deployUsingFactory = async (factory, params, name) => {
    let adapter = await factory.deploy(...params);

    if (adapter) {
        await adapter.deployed();
        console.log(`${params[params.length - 2]} :`, adapter.address);

        // verify contracts
        await verify({
            contractName: params[params.length - 2],
            address: adapter.address,
            constructorArguments: [...params],
            contractPath: adapterPaths[name],
        });
    }

    return { name: params[params.length - 2], address: adapter.address };
};

export { verify, deployUsingFactory };
