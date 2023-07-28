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

const checkPendingWithClaim = async (investor, ybNft, user, tokenId, performanceFee) => {
    const treasury = await investor.treasury();
    const fundManager = await ybNft.ownerOf(tokenId);

    const userPending = await investor.pendingReward(tokenId, user.address);
    const bTreasury = await ethers.provider.getBalance(treasury);
    const bFManager = await ethers.provider.getBalance(fundManager);

    const opTokenInfo = await ybNft.opTokenInfos(tokenId);
    const opToken = await ethers.getContractAt("IERC20", opTokenInfo.token);

    if (opToken.address !== ethers.constants.AddressZero) {
        expect(userPending.withdrawable).gt(0);

        const beforeAmt = await opToken.balanceOf(user.address);

        const claimTx = await investor.connect(user).claim(tokenId);
        const claimTxResp = await claimTx.wait();
        const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(BigNumber.from(claimTxResp.gasUsed));

        const afterAmt = await opToken.balanceOf(user.address);
        const aTreasury = await ethers.provider.getBalance(treasury);
        const aFManager = await ethers.provider.getBalance(fundManager);
        const actualPending = BigNumber.from(afterAmt).add(gasAmt).sub(beforeAmt);

        // actualPending in 2% range of estimatePending
        expect(actualPending).gte(0);

        // check treasury balance and fundManager balance change
        expect(BigNumber.from(aFManager).sub(bFManager)).gte(BigNumber.from(aTreasury).sub(bTreasury).mul(4));
    } else {
        expect(userPending.withdrawable).gt(0);

        const estimatePending = BigNumber.from(userPending.withdrawable)
            .mul(1e4 - performanceFee)
            .div(1e4);

        const beforeBNB = await ethers.provider.getBalance(user.address);

        const claimTx = await investor.connect(user).claim(tokenId);
        const claimTxResp = await claimTx.wait();
        const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(BigNumber.from(claimTxResp.gasUsed));

        const afterBNB = await ethers.provider.getBalance(user.address);
        const aTreasury = await ethers.provider.getBalance(treasury);
        const aFManager = await ethers.provider.getBalance(fundManager);
        const actualPending = BigNumber.from(afterBNB).add(gasAmt).sub(beforeBNB);

        // actualPending in 2% range of estimatePending
        expect(actualPending).gte(estimatePending.mul(95).div(1e2));

        // check treasury balance and fundManager balance change
        expect(BigNumber.from(aFManager).sub(bFManager)).gte(BigNumber.from(aTreasury).sub(bTreasury).mul(4));
    }
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
