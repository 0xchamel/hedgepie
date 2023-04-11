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

    log.info(
        `Verifying "${contractName}" on network: ${hre.network.name}, address: ${address}`
    );
    try {
        await hre.run("verify:verify", {
            address,
            constructorArguments,
            contract: contractPath,
        });
        log.info(
            `Verifying "${contractName}" on network: ${hre.network.name}, address: ${address} was succeeded.`
        );
    } catch (e) {
        log.error(`Verification error: ${e}`);
    }
}

const deployUsingFactory = async (factory, params, name) => {
    let adapter;
    if (params.length === 4) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3]
        );
    }

    if (params.length === 5) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4]
        );
    }

    if (params.length === 6) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5]
        );
    }

    if (params.length === 7) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5],
            params[6]
        );
    }

    if (params.length === 8) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5],
            params[6],
            params[7]
        );
    }

    if (params.length === 9) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5],
            params[6],
            params[7],
            params[8]
        );
    }

    if (params.length === 10) {
        adapter = await factory.deploy(
            params[0],
            params[1],
            params[2],
            params[3],
            params[4],
            params[5],
            params[6],
            params[7],
            params[8],
            params[9]
        );
    }

    if (adapter) {
        await adapter.deployed();
        console.log(`${params[params.length - 2]} :`, adapter.address);

        // verify contracts
        if (params.length === 4) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 5) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                    params[4],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 6) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                    params[5],
                    params[6],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 7) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                    params[4],
                    params[5],
                    params[6],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 8) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 9) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                    params[4],
                    params[5],
                    params[6],
                    params[7],
                    params[8],
                ],
                contractPath: adapterPaths[name],
            });
        }

        if (params.length === 10) {
            await verify({
                contractName: params[params.length - 2],
                address: adapter.address,
                constructorArguments: [
                    params[0],
                    params[1],
                    params[2],
                    params[3],
                    params[4],
                    params[5],
                    params[6],
                    params[7],
                    params[8],
                    params[9],
                ],
                contractPath: adapterPaths[name],
            });
        }
    }
};

export { verify, deployUsingFactory };
