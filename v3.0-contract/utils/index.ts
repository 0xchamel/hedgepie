import hre, { upgrades } from "hardhat";
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

const deployUsingFactory = async (beacon, factory, params, name, isVerify = false) => {
    // let adapter = await factory.deploy(...params);
    let adapter = await upgrades.deployBeaconProxy(beacon, factory, [...params]);

    if (adapter) {
        await adapter.deployed();
        console.log(`${params[params.length - 2]} :`, adapter.address);

        if (isVerify) {
            // verify contracts
            await verify({
                contractName: params[params.length - 2],
                address: await beacon.implementation(),
                constructorArguments: [],
                contractPath: adapterPaths[name],
            });
        }
    }

    return { name: params[params.length - 2], address: adapter.address };
};

export { verify, deployUsingFactory };
