const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setPath } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

describe("AlpacaAUSDPoolAdapter Integration Test", function () {
    before("Deploy contract", async function () {
        const [owner, alice, bob, treasury] = await ethers.getSigners();

        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const strategy = "0x158Da805682BdC8ee32d52833aD41E74bb951E59"; // USDT Vault
        const stakingToken = "0x55d398326f99059fF775485246999027B3197955"; // Binance-Peg BSC-USD (BSC-USD)
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address

        this.performanceFee = 50;
        this.owner = owner;
        this.alice = alice;
        this.bob = bob;

        this.bobAddr = bob.address;
        this.aliceAddr = alice.address;
        this.treasuryAddr = treasury.address;

        // Deploy Alpada ausd pool Adapter contract
        const AlpacaAdapter = await adapterFixtureBsc("AlpacaAUSDAdapter");
        this.aAdapter = await AlpacaAdapter.deploy(
            strategy,
            stakingToken,
            swapRouter,
            wbnb,
            "Alpaca::AUSD::USDT"
        );
        await this.aAdapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.aAdapter,
                this.treasuryAddr,
                stakingToken,
                this.performanceFee
            );

        await setPath(this.aAdapter, wbnb, stakingToken);

        console.log("Owner: ", this.owner.address);
        console.log("Investor: ", this.investor.address);
        console.log("Strategy: ", strategy);
        console.log("AlpacaAUSDPoolAdapter: ", this.aAdapter.address);
    });

    describe("depositBNB function test", function () {
        it("(1) should be reverted when nft tokenId is invalid", async function () {
            // deposit to nftID: 3
            const depositAmount = ethers.utils.parseEther("1");
            await expect(
                this.investor
                    .connect(this.owner)
                    .depositBNB(3, depositAmount.toString(), {
                        gasPrice: 21e9,
                        value: depositAmount,
                    })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2) should be reverted when amount is 0", async function () {
            // deposit to nftID: 1
            const depositAmount = ethers.utils.parseEther("0");
            await expect(
                this.investor.depositBNB(1, depositAmount.toString(), {
                    gasPrice: 21e9,
                })
            ).to.be.revertedWith("Error: Insufficient BNB");
        });

        it("(3) deposit should success for Alice", async function () {
            const depositAmount = ethers.utils.parseEther("10");
            await this.investor
                .connect(this.alice)
                .depositBNB(1, depositAmount, {
                    gasPrice: 21e9,
                    value: depositAmount,
                });

            const aliceInfo = (
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            expect(Number(aliceInfo) / Math.pow(10, 18)).to.eq(10);

            const aliceAdapterInfos = await this.aAdapter.userAdapterInfos(
                this.aliceAddr,
                1
            );
            const adapterInfos = await this.aAdapter.adapterInfos(1);
            expect(BigNumber.from(adapterInfos.totalStaked)).to.eq(
                BigNumber.from(aliceAdapterInfos.amount)
            );
        });

        it("(4) deposit should success for Bob", async function () {
            const beforeAdapterInfos = await this.aAdapter.adapterInfos(1);
            const depositAmount = ethers.utils.parseEther("10");

            await this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                gasPrice: 21e9,
                value: depositAmount,
            });

            await this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                gasPrice: 21e9,
                value: depositAmount,
            });

            const bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            expect(Number(bobInfo) / Math.pow(10, 18)).to.eq(20);

            const bobAdapterInfos = await this.aAdapter.userAdapterInfos(
                this.bobAddr,
                1
            );
            expect(BigNumber.from(bobAdapterInfos.amount).gt(0)).to.eq(true);

            const afterAdapterInfos = await this.aAdapter.adapterInfos(1);

            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);
        });

        it("(5) test pendingReward function and protocol-fee", async function () {
            const pending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            );
            expect(BigNumber.from(pending[0]).gt(0)).to.be.eq(true);
        });

        it("(6) test TVL & participants", async function () {
            const nftInfo = await this.adapterInfo.adapterInfo(1);

            expect(
                Number(
                    ethers.utils.formatEther(
                        BigNumber.from(nftInfo.tvl).toString()
                    )
                )
            ).to.be.eq(30) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "2"
                );
        });
    });

    describe("check withdrawal amount", function() {
        it("(1) check withdrawal amount for alice", async function() {
            const alicePending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            )
            expect(alicePending.withdrawable).to.be.eq(0)
            expect(alicePending.amountOut).gt(0)
        })

        it("(2) check withdrawal amount for bob", async function() {
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            )
            expect(bobPending.withdrawable).to.be.eq(0)
            expect(bobPending.amountOut).gt(0)
        })
    });

    describe("withdrawBNB() function test", function () {
        it("(1) revert when nft tokenId is invalid", async function () {
            // withdraw to nftID: 3
            await expect(
                this.investor
                    .connect(this.owner)
                    .withdrawBNB(3, { gasPrice: 21e9 })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2) should receive the BNB successfully after withdraw function for Alice", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(this.aliceAddr);
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            const alicePending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            );
            let aliceInfo = (
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;

            const gasPrice = 21e9;
            const gas = await this.investor
                .connect(this.alice)
                .estimateGas.withdrawBNB(1, { gasPrice });
            await expect(
                this.investor.connect(this.alice).withdrawBNB(1, { gasPrice })
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.aliceAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            // check protocol fee and amountOut
            const rewardAmt = afterBNB.sub(beforeBNB);
            const afterOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let actualPending = rewardAmt.add(gas.mul(gasPrice));
            if (actualPending.gt(aliceInfo)) {
                console.log(alicePending, actualPending, aliceInfo, "pendingpendingpendingpendingpending")
                actualPending = actualPending.sub(BigNumber.from(aliceInfo));
                const protocolFee = afterOwnerBNB.sub(beforeOwnerBNB);
                expect(protocolFee).to.gte(0);
                expect(actualPending).to.be.within(
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .sub(gas.mul(gasPrice)),
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .add(gas.mul(gasPrice))
                );

                const estimatePending = BigNumber.from(alicePending.amountOut).mul(
                    1e4 - this.performanceFee
                ).div(1e4)
                console.log(estimatePending, actualPending, aliceInfo, "pendingpendingpendingpendingpending")
                expect(actualPending).gte(
                    estimatePending.mul(98).div(1e2)
                )
            }

            aliceInfo = (
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            expect(aliceInfo).to.eq(BigNumber.from(0));

            const bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            const bobDeposit = Number(bobInfo) / Math.pow(10, 18);
            expect(bobDeposit).to.eq(20);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            const nftInfo = await this.adapterInfo.adapterInfo(1);

            expect(
                Number(
                    ethers.utils.formatEther(
                        BigNumber.from(nftInfo.tvl).toString()
                    )
                )
            ).to.be.eq(20) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "1"
                );
        });

        it("(4) should receive the BNB successfully after withdraw function for Bob", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(this.bobAddr);
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            );
            let bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;

            const gasPrice = 21e9;
            const gas = await this.investor
                .connect(this.bob)
                .estimateGas.withdrawBNB(1, { gasPrice });
            await expect(
                this.investor.connect(this.bob).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.bobAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            // check protocol fee and amountOut
            const rewardAmt = afterBNB.sub(beforeBNB);
            let actualPending = rewardAmt.add(gas.mul(gasPrice));
            if (actualPending.gt(bobInfo)) {
                actualPending = actualPending.sub(bobInfo);
                const afterOwnerBNB = await ethers.provider.getBalance(
                    this.treasuryAddr
                );
                const protocolFee = afterOwnerBNB.sub(beforeOwnerBNB);
                expect(protocolFee).to.gt(0);
                expect(actualPending).to.be.within(
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .sub(gas.mul(gasPrice)),
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .add(gas.mul(gasPrice))
                );

                const estimatePending = BigNumber.from(bobPending.amountOut).mul(
                    1e4 - this.performanceFee
                ).div(1e4)
                expect(actualPending).gte(
                    estimatePending.mul(98).div(1e2)
                )
            }

            bobInfo = (await this.aAdapter.userAdapterInfos(this.bobAddr, 1))
                .invested;
            expect(bobInfo).to.eq(BigNumber.from(0));
        });

        it("(5) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.adapterInfo.adapterInfo(1);

            expect(
                Number(
                    ethers.utils.formatEther(
                        BigNumber.from(nftInfo.tvl).toString()
                    )
                )
            ).to.be.eq(0) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "0"
                );
        });
    });
});
