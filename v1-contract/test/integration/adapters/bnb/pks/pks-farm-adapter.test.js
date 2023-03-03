const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setPath } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

describe("PancakeSwapFarmLPAdapter Integration Test", function () {
    before("Deploy contract", async function () {
        const [owner, alice, bob, treasury, kyle, jerry, user1, user2] =
            await ethers.getSigners();

        const performanceFee = 500;
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
        const strategy = "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652"; // MasterChef v2 pks
        const lpToken = "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0"; // WBNB-CAKE LP

        this.performanceFee = performanceFee;
        this.wbnb = wbnb;
        this.cake = cake;
        this.poolID = 2;

        this.owner = owner;
        this.alice = alice;
        this.bob = bob;
        this.kyle = kyle;
        this.jerry = jerry;
        this.user1 = user1;
        this.user2 = user2;
        this.pksRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

        this.bobAddr = bob.address;
        this.aliceAddr = alice.address;
        this.treasuryAddr = treasury.address;
        this.accTokenPerShare = BigNumber.from(0);

        // Deploy PancakeSwapFarmLPAdapterBsc contract
        const PancakeSwapFarmLPAdapterBsc = await adapterFixtureBsc(
            "PancakeSwapFarmLPAdapterBsc"
        );

        this.adapter = await PancakeSwapFarmLPAdapterBsc.deploy(
            this.poolID, // pid
            strategy,
            lpToken,
            this.cake,
            this.pksRouter,
            this.wbnb,
            "PancakeSwap::Farm::CAKE-WBNB"
        );
        await this.adapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.adapter,
                treasury.address,
                lpToken,
                this.performanceFee
            );

        await setPath(this.adapter, this.wbnb, this.cake);

        console.log("Owner: ", this.owner.address);
        console.log("Investor: ", this.investor.address);
        console.log("Strategy: ", strategy);
        console.log("Info: ", this.adapterInfo.address);
        console.log("PancakeSwapFarmLPAdapterBsc: ", this.adapter.address);
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
            await expect(
                this.investor.connect(this.alice).depositBNB(1, depositAmount, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.aliceAddr, this.ybNft.address, 1, depositAmount);

            const aliceInfo = (
                await this.adapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            const fTokenAmount = await this.adapter.getfTokenAmount(
                1,
                this.aliceAddr
            );
            expect(Number(aliceInfo) / Math.pow(10, 18)).to.eq(10) &&
                expect(Number(fTokenAmount) / Math.pow(10, 18)).to.eq(10);

            // Check accTokenPerShare Info
            this.accTokenPerShare = (
                await this.adapter.mAdapter()
            ).accTokenPerShare;
            expect(BigNumber.from(this.accTokenPerShare)).to.eq(
                BigNumber.from(0)
            );
        });

        it("(4) deposit should success for Bob", async function () {
            // wait 40 mins
            for (let i = 0; i < 7200; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const beforeAdapterInfos = await this.adapter.mAdapter();
            const depositAmount = ethers.utils.parseEther("10");

            await expect(
                this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.bobAddr, this.ybNft.address, 1, depositAmount);

            await expect(
                this.investor.connect(this.bob).depositBNB(1, depositAmount, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "DepositBNB")
                .withArgs(this.bobAddr, this.ybNft.address, 1, depositAmount);

            const bobInfo = (
                await this.adapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            expect(Number(bobInfo) / Math.pow(10, 18)).to.eq(20);

            const afterAdapterInfos = await this.adapter.mAdapter();

            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            // Check accTokenPerShare Info
            expect(
                BigNumber.from(
                    (await this.adapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.adapter.mAdapter()
            ).accTokenPerShare;
        });

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
        });
    });

    describe("claim() function test", function () {
        it("(1) check withdrawable and claim for alice", async function () {
            // wait 1 day
            for (let i = 0; i < 1800; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const alicePending = await this.investor.pendingReward(
                1,
                this.aliceAddr
            );
            expect(alicePending.withdrawable).gt(0);

            const estimatePending = BigNumber.from(alicePending.withdrawable)
                .mul(1e4 - this.performanceFee)
                .div(1e4);

            const beforeBNB = await ethers.provider.getBalance(this.aliceAddr);

            const claimTx = await this.investor.connect(this.alice).claim(1);
            const claimTxResp = await claimTx.wait();
            const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(
                BigNumber.from(claimTxResp.gasUsed)
            );

            const afterBNB = await ethers.provider.getBalance(this.aliceAddr);
            const actualPending = BigNumber.from(afterBNB)
                .add(gasAmt)
                .sub(beforeBNB);

            // actualPending in 2% range of estimatePending
            expect(actualPending).gte(estimatePending.mul(98).div(1e2));
        });

        it("(2) check withdrawable and claim for bob", async function () {
            const bobPending = await this.investor.pendingReward(
                1,
                this.bobAddr
            );
            expect(bobPending.withdrawable).gt(0);

            const estimatePending = BigNumber.from(bobPending.withdrawable)
                .mul(1e4 - this.performanceFee)
                .div(1e4);

            const beforeBNB = await ethers.provider.getBalance(this.bobAddr);

            const claimTx = await this.investor.connect(this.bob).claim(1);
            const claimTxResp = await claimTx.wait();
            const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(
                BigNumber.from(claimTxResp.gasUsed)
            );

            const afterBNB = await ethers.provider.getBalance(this.bobAddr);
            const actualPending = BigNumber.from(afterBNB)
                .add(gasAmt)
                .sub(beforeBNB);

            // actualPending in 2% range of estimatePending
            expect(actualPending).gte(estimatePending.mul(98).div(1e2));
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
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let aliceInfo = (
                await this.adapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;

            await expect(
                this.investor.connect(this.alice).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.aliceAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            aliceInfo = (await this.adapter.userAdapterInfos(this.aliceAddr, 1))
                .invested;
            expect(aliceInfo).to.eq(BigNumber.from(0));

            const bobInfo = (
                await this.adapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            const bobDeposit = Number(bobInfo) / Math.pow(10, 18);
            expect(bobDeposit).to.eq(20);

            expect(
                BigNumber.from(
                    (await this.adapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.adapter.mAdapter()
            ).accTokenPerShare;
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
            let bobInfo = (await this.adapter.userAdapterInfos(this.bobAddr, 1))
                .invested;

            await expect(
                this.investor.connect(this.bob).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.bobAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            bobInfo = (await this.adapter.userAdapterInfos(this.bobAddr, 1))
                .invested;
            expect(bobInfo).to.eq(BigNumber.from(0));

            // Check accTokenPerShare Info
            expect(
                BigNumber.from(
                    (await this.adapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.adapter.mAdapter()
            ).accTokenPerShare;
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

    describe("pendingReward(), claim() function tests and protocol-fee test", function () {
        it("test with token1 and token2", async function () {
            await this.investor
                .connect(this.kyle)
                .depositBNB(1, ethers.utils.parseEther("10"), {
                    gasPrice: 21e9,
                    value: ethers.utils.parseEther("10"),
                });

            await this.investor
                .connect(this.jerry)
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

            // deposit from other user to update accTokenPerShare values
            await this.investor
                .connect(this.alice)
                .depositBNB(2, ethers.utils.parseEther("1"), {
                    gasPrice: 21e9,
                    value: ethers.utils.parseEther("1"),
                });

            // check pending rewards
            const pending1 = await this.investor.pendingReward(
                1,
                this.kyle.address
            );
            const pending2 = await this.investor.pendingReward(
                2,
                this.jerry.address
            );
            expect(
                BigNumber.from(pending2[0]).gt(
                    BigNumber.from(pending1[0]).mul(9)
                )
            ).to.eq(true);

            // claim rewards
            let treasuryAmt1 = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            const beforeAmt1 = await ethers.provider.getBalance(
                this.kyle.address
            );
            const tx1 = await (
                await this.investor.connect(this.kyle).claim(1)
            ).wait();
            const afterAmt1 = await ethers.provider.getBalance(
                this.kyle.address
            );
            const actualReward1 = afterAmt1
                .add(tx1.gasUsed.mul(tx1.effectiveGasPrice))
                .sub(beforeAmt1);
            treasuryAmt1 = (
                await ethers.provider.getBalance(this.treasuryAddr)
            ).sub(treasuryAmt1);

            // check protocol fee
            expect(actualReward1.div(19)).to.eq(treasuryAmt1);

            let treasuryAmt2 = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            const beforeAmt2 = await ethers.provider.getBalance(
                this.jerry.address
            );
            const tx2 = await (
                await this.investor.connect(this.jerry).claim(2)
            ).wait();
            const afterAmt2 = await ethers.provider.getBalance(
                this.jerry.address
            );
            const actualReward2 = afterAmt2
                .add(tx2.gasUsed.mul(tx2.effectiveGasPrice))
                .sub(beforeAmt2);
            treasuryAmt2 = (
                await ethers.provider.getBalance(this.treasuryAddr)
            ).sub(treasuryAmt2);

            // check protocol fee
            expect(actualReward2.div(19)).to.eq(treasuryAmt2);

            // Check mixed adapter reward results
            expect(
                BigNumber.from(actualReward2).gt(
                    BigNumber.from(actualReward1).mul(9)
                )
            ).to.eq(true);

            // Successfully withdraw
            await expect(
                this.investor.connect(this.kyle).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            await expect(
                this.investor.connect(this.jerry).withdrawBNB(2)
            ).to.emit(this.investor, "WithdrawBNB");
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

            const adaInvested1 = await this.adapter.adapterInvested(1);
            const adaInvested2 = await this.adapter.adapterInvested(2);

            await this.ybNft.updateAllocations(1, [5000]);

            expect(
                BigNumber.from(adaInvested2).eq(
                    BigNumber.from(await this.adapter.adapterInvested(2))
                )
            ).to.eq(true);
            expect(
                BigNumber.from(await this.adapter.adapterInvested(1)).lt(
                    BigNumber.from(adaInvested1).mul(5).div(10)
                )
            ).to.eq(true);
            expect(
                BigNumber.from(await this.adapter.adapterInvested(1)).gt(
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
