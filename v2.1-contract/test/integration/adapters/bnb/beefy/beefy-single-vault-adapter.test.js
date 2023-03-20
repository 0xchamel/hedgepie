const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setPath } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
    adapterFixtureBscWithLib,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

describe("BeefySingleVaultAdapter Integration Test", function () {
    before("Deploy contract", async function () {
        const [owner, alice, bob, treasury, user1, user2] =
            await ethers.getSigners();

        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const stakingToken = "0x2170Ed0880ac9A755fd29B2688956BD959F933F8"; // Binance-Peg Ethereum Token (ETH)
        const strategy = "0x725E14C3106EBf4778e01eA974e492f909029aE8"; // Moo Valas ETH
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address

        this.owner = owner;
        this.alice = alice;
        this.bob = bob;
        this.user1 = user1;
        this.user2 = user2;
        this.performanceFee = 50;

        this.bobAddr = bob.address;
        this.aliceAddr = alice.address;
        this.treasuryAddr = treasury.address;

        const Lib = await ethers.getContractFactory("HedgepieLibraryBsc");
        this.lib = await Lib.deploy();

        // Deploy Beefy LP Vault Adapter contract
        const beefyAdapter = await adapterFixtureBscWithLib(
            "BeefyVaultAdapter",
            this.lib
        );
        this.aAdapter = await beefyAdapter.deploy(
            strategy,
            stakingToken,
            ethers.constants.AddressZero,
            swapRouter,
            wbnb,
            "Beefy::Vault::ETH"
        );
        await this.aAdapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.aAdapter,
                treasury.address,
                stakingToken,
                this.performanceFee,
                this.lib
            );

        await setPath(this.aAdapter, wbnb, stakingToken);

        this.repayToken = await ethers.getContractAt("IBEP20", strategy);

        console.log("Owner: ", this.owner.address);
        console.log("Investor: ", this.investor.address);
        console.log("Strategy: ", strategy);
        console.log("BeefySingleVaultAdapter: ", this.aAdapter.address);
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
            const beforeRepay = await this.repayToken.balanceOf(
                this.aAdapter.address
            );
            const depositAmount = ethers.utils.parseEther("10");
            await expect(
                this.investor.connect(this.alice).depositBNB(1, depositAmount, {
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.aliceAddr, this.ybNft.address, 1, depositAmount);

            const aliceAdapterInfos = await this.aAdapter.userAdapterInfos(
                this.aliceAddr,
                1
            );
            expect(BigNumber.from(aliceAdapterInfos.invested).gt(0)).to.eq(
                true
            );

            const adapterInfos = await this.aAdapter.mAdapter();
            expect(BigNumber.from(adapterInfos.totalStaked)).to.gt(0);

            const afterRepay = await this.repayToken.balanceOf(
                this.aAdapter.address
            );
            expect(BigNumber.from(adapterInfos.totalStaked)).to.eq(
                BigNumber.from(afterRepay).sub(BigNumber.from(beforeRepay))
            );
        });

        it("(4) deposit should success for Bob", async function () {
            const beforeRepay = await this.repayToken.balanceOf(
                this.aAdapter.address
            );
            const beforeAdapterInfos = await this.aAdapter.mAdapter();

            const depositAmount = ethers.utils.parseEther("10");
            await expect(
                this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.bobAddr, this.ybNft.address, 1, depositAmount);

            await expect(
                this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.bobAddr, this.ybNft.address, 1, depositAmount);

            const afterAdapterInfos = await this.aAdapter.mAdapter();
            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            const afterRepay = await this.repayToken.balanceOf(
                this.aAdapter.address
            );
            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).sub(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(
                BigNumber.from(afterRepay).sub(BigNumber.from(beforeRepay))
            );
        }).timeout(50000000);

        it("(5) test TVL & participants", async function () {
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

            const pendingInfo = await this.aAdapter.pendingReward(
                1,
                this.alice.address
            );
            expect(pendingInfo[0]).to.gte(0);
        });
    });

    describe("check withdrawal amount", function () {
        it("(1) check withdrawal amount for alice", async function () {
            const alicePending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            );
            expect(alicePending.withdrawable).to.be.eq(0);
            expect(alicePending.amountOut).eq(0);
        });

        it("(2) check withdrawal amount for bob", async function () {
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            );
            expect(bobPending.withdrawable).to.be.eq(0);
            expect(bobPending.amountOut).eq(0);
        });
    });

    describe("withdrawBNB() function test", function () {
        it("(1) revert when nft tokenId is invalid", async function () {
            for (let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

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
            );
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
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
                );

                const estimatePending = BigNumber.from(alicePending.amountOut)
                    .mul(1e4 - this.performanceFee)
                    .div(1e4);
                expect(actualPending).gte(estimatePending.mul(98).div(1e2));
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
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            );
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;

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
                );

                const estimatePending = BigNumber.from(bobPending.amountOut)
                    .mul(1e4 - this.performanceFee)
                    .div(1e4);
                expect(actualPending).gte(estimatePending.mul(98).div(1e2));
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

    describe("Edit fund flow", function () {
        it("test with token1 and token2 - updateAllocations", async function () {
            await this.investor
                .connect(this.user1)
                .depositBNB(1, ethers.utils.parseEther("10"), {
                    gasPrice: 21e9,
                    value: ethers.utils.parseEther("10"),
                });

            await this.investor
                .connect(this.user2)
                .depositBNB(2, ethers.utils.parseEther("100"), {
                    gasPrice: 21e9,
                    value: ethers.utils.parseEther("100"),
                });

            // wait 40 mins
            for (let i = 0; i < 7200; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const adaInvested1 = await this.aAdapter.adapterInvested(1);
            const adaInvested2 = await this.aAdapter.adapterInvested(2);

            await this.ybNft.updateAllocations(1, [5000]);

            expect(
                BigNumber.from(adaInvested2).eq(
                    BigNumber.from(await this.aAdapter.adapterInvested(2))
                )
            ).to.eq(true);
            expect(
                BigNumber.from(await this.aAdapter.adapterInvested(1)).lt(
                    BigNumber.from(adaInvested1).mul(5).div(10)
                )
            ).to.eq(true);
            expect(
                BigNumber.from(await this.aAdapter.adapterInvested(1)).gt(
                    BigNumber.from(adaInvested1).mul(4).div(10)
                )
            ).to.eq(true);

            // Successfully withdraw
            await expect(
                this.investor.connect(this.user1).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");
            await expect(
                this.investor.connect(this.user2).withdrawBNB(2)
            ).to.emit(this.investor, "WithdrawBNB");
        });
    });
});
