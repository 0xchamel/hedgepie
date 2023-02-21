const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setPath, encode } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

async function doubleWantLockedTotal(address, slot, current) {
    await network.provider.send("hardhat_setStorageAt", [
        address,
        slot,
        encode(["uint256"], [BigNumber.from(current).mul(2).toString()]),
    ]);
}

describe("AutoVaultAdatperBsc Integration Test", function () {
    before("Deploy contract", async function () {
        const [owner, alice, bob, treasury] = await ethers.getSigners();

        this.wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        this.cake = "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82";
        this.strategy = "0x0895196562C7868C5Be92459FaE7f877ED450452"; // MasterChef
        this.vStrategy = "0xcFF7815e0e85a447b0C21C94D25434d1D0F718D1"; // vStrategy of vault
        this.stakingToken = "0x0ed7e52944161450477ee417de9cd3a859b14fd0"; // WBNB-Cake LP
        this.router = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // LP Router
        this.swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks router address
        this.name = "AutoFarm::Vault::WBNB-CAKE";
        this.poolID = 619;
        this.performanceFee = 100;

        this.owner = owner;
        this.alice = alice;
        this.bob = bob;

        this.bobAddr = bob.address;
        this.aliceAddr = alice.address;
        this.treasuryAddr = treasury.address;

        // Deploy AutoVaultAdapterBsc contract
        const AutoFarmAdapter = await adapterFixtureBsc("AutoVaultAdapterBsc");
        this.adapter = await AutoFarmAdapter.deploy(
            this.poolID,
            this.strategy,
            this.vStrategy,
            this.stakingToken,
            this.router,
            this.swapRouter,
            this.wbnb,
            this.name
        );
        await this.adapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.adapter,
                treasury.address,
                this.stakingToken,
                this.performanceFee
            );

        await setPath(this.adapter, this.wbnb, this.cake);

        this.ctVStrategy = await ethers.getContractAt(
            "IVaultStrategy",
            this.vStrategy
        );

        console.log("Owner: ", this.owner.address);
        console.log("Investor: ", this.investor.address);
        console.log("Strategy: ", this.strategy);
        console.log("Info: ", this.adapterInfo.address);
        console.log("AutofarmVaultAdapterBsc: ", this.adapter.address);
    });

    describe("depositBNB() function test", function () {
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
                await this.adapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            expect(Number(aliceInfo) / Math.pow(10, 18)).to.eq(10);

            const aliceAdapterInfos = await this.adapter.userAdapterInfos(
                this.aliceAddr,
                1
            );
            const adapterInfos = await this.adapter.adapterInfos(1);
            expect(BigNumber.from(adapterInfos.totalStaked)).to.eq(
                BigNumber.from(aliceAdapterInfos.amount)
            );
        });

        it("(4) deposit should success for Bob", async function () {
            const beforeAdapterInfos = await this.adapter.adapterInfos(1);
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
                await this.adapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            expect(Number(bobInfo) / Math.pow(10, 18)).to.eq(20);

            const bobAdapterInfos = await this.adapter.userAdapterInfos(
                this.bobAddr,
                1
            );
            expect(BigNumber.from(bobAdapterInfos.amount).gt(0)).to.eq(true);

            const afterAdapterInfos = await this.adapter.adapterInfos(1);

            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);
        });

        it("(5) test pendingReward function and protocol-fee", async function () {
            // double the staked token amount
            await doubleWantLockedTotal(
                this.vStrategy,
                "0xe",
                await this.ctVStrategy.wantLockedTotal()
            );

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
            const alicePending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            )
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let aliceInfo = (
                await this.adapter.userAdapterInfos(this.aliceAddr, 1)
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
                actualPending = actualPending.sub(BigNumber.from(aliceInfo));
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
                )

                const estimatePending = BigNumber.from(alicePending.amountOut).mul(
                    1e4 - this.performanceFee
                ).div(1e4)
                expect(actualPending).gte(
                    estimatePending.mul(98).div(1e2)
                )
            }

            aliceInfo = (await this.adapter.userAdapterInfos(this.aliceAddr, 1))
                .invested;
            expect(aliceInfo).to.eq(BigNumber.from(0));

            const bobInfo = (
                await this.adapter.userAdapterInfos(this.bobAddr, 1)
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
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            )
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let bobInfo = (await this.adapter.userAdapterInfos(this.bobAddr, 1))
                .invested;
            
            const gasPrice = 21e9;
            const gas = await this.investor
                .connect(this.bob)
                .estimateGas.withdrawBNB(1, { gasPrice });
            await expect(
                this.investor.connect(this.bob).withdrawBNB(1, { gasPrice })
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
                )

                const estimatePending = BigNumber.from(bobPending.amountOut).mul(
                    1e4 - this.performanceFee
                ).div(1e4)
                expect(actualPending).gte(
                    estimatePending.mul(98).div(1e2)
                )
            }

            bobInfo = (await this.adapter.userAdapterInfos(this.bobAddr, 1))
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
