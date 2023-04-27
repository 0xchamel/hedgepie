const { expect } = require("chai");
const { ethers } = require("hardhat");

const BigNumber = ethers.BigNumber;

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

async function forkBNBNetwork(blockNumber = -1) {
    await hre.network.provider.request({
        method: "hardhat_reset",
        params: [
            {
                forking: {
                    jsonRpcUrl: "https://rpc.ankr.com/bsc",
                    blockNumber: blockNumber === -1 ? 25710942 : blockNumber,
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
    await pathFinder.connect(pathManager).setPath(router, paths[0], paths[paths.length - 1], paths);

    const tmp = paths[0];
    paths[0] = paths[paths.length - 1];
    paths[paths.length - 1] = tmp;

    await pathFinder.connect(pathManager).setPath(router, paths[0], paths[paths.length - 1], paths);
}

function encode(types, values) {
    return ethers.utils.defaultAbiCoder.encode(types, values);
}

const checkPendingWithClaim = async (investor, user, tokenId, performanceFee) => {
    const userPending = await investor.pendingReward(tokenId, user.address);
    expect(userPending.withdrawable).gt(0);

    const estimatePending = BigNumber.from(userPending.withdrawable)
        .mul(1e4 - performanceFee)
        .div(1e4);

    const beforeBNB = await ethers.provider.getBalance(user.address);

    const claimTx = await investor.connect(user).claim(tokenId);
    const claimTxResp = await claimTx.wait();
    const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(BigNumber.from(claimTxResp.gasUsed));

    const afterBNB = await ethers.provider.getBalance(user.address);
    const actualPending = BigNumber.from(afterBNB).add(gasAmt).sub(beforeBNB);

    // actualPending in 2% range of estimatePending
    expect(actualPending).gte(estimatePending.mul(95).div(1e2));
};

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
    checkPendingWithClaim,
};
