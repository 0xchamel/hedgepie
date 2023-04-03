async function forkETHNetwork() {
    await hre.network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: "https://rpc.ankr.com/eth",
                },
            },
        ],
    });
}

async function forkBNBNetwork() {
    await hre.network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: "https://rpc.ankr.com/bsc",
                },
            },
        ],
    });
}

async function forkPolygonNetwork() {
    await hre.network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: "https://polygon-rpc.com",
                },
            },
        ],
    });
}

async function setPath(pathFinder, pathManager, router, paths) {
    await pathFinder.connect(pathManager).setRouter(router, true);
    await pathFinder
        .connect(pathManager)
        .setPath(router, paths[0], paths[paths.length - 1], paths);

    const tmp = paths[0];
    paths[0] = paths[paths.length - 1];
    paths[paths.length - 1] = tmp;

    await pathFinder
        .connect(pathManager)
        .setPath(router, paths[0], paths[paths.length - 1], paths);
}

function encode(types, values) {
    return ethers.utils.defaultAbiCoder.encode(types, values);
}

const unlockAccount = async (address) => {
    await hre.network.provider.send("hardhat_impersonateAccount", [address]);
    return hre.ethers.provider.getSigner(address);
};

module.exports = {
    encode,
    setPath,
    forkETHNetwork,
    forkBNBNetwork,
    forkPolygonNetwork,
    unlockAccount,
};
