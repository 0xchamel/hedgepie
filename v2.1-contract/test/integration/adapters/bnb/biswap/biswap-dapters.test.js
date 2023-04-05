const { expect } = require("chai");
const { ethers } = require("hardhat");

const {
    setPath,
    checkPendingWithClaim,
} = require("../../../../shared/utilities");
const {
    setupHedgepie,
    setupBscAdapterWithLib,
    mintNFT,
} = require("../../../../shared/setup");

const BigNumber = ethers.BigNumber;

describe("Biswap Adapters Integration Test", function () {
    before("Deploy contract", async function () {
        [
            this.governor,
            this.pathManager,
            this.adapterManager,
            this.treasury,
            this.alice,
            this.bob,
            this.kyle,
            this.jerry,
            this.user1,
            this.user2,
        ] = await ethers.getSigners();

        // Get base contracts
        [
            this.investor,
            this.authority,
            this.ybNft,
            this.adapterList,
            this.pathFinder,
            this.lib,
        ] = await setupHedgepie(
            this.governor,
            this.pathManager,
            this.adapterManager,
            this.treasury
        );

        const poolID = 9;
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const usdt = "0x55d398326f99059ff775485246999027b3197955";
        const bsw = "0x965f527d9159dce6288a2219db51fc6eef120dd1";
        const lpToken = "0x2b30c317ceDFb554Ec525F85E79538D59970BEb0"; // USDT-BSW LP
        const strategy = "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739"; // MasterChef Biswap
        const biswapRouter = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8";

        this.performanceFee = 500;
        this.accRewardShare = BigNumber.from(0);

        // Deploy BiswapFarmLPAdapterBsc contract
        const BiswapFarmLPAdapterBsc = await setupBscAdapterWithLib(
            "BiSwapFarmLPAdapterBsc",
            this.lib
        );
        this.adapter = [0, 0];
        this.adapter[0] = await BiswapFarmLPAdapterBsc.deploy(
            poolID, // pid
            strategy,
            lpToken,
            bsw,
            biswapRouter,
            biswapRouter,
            wbnb,
            "Biswap::Farm::USDT-BSW",
            this.authority.address
        );
        await this.adapter[0].deployed();

        // Deploy BiswapBSWPoolAdapterBsc contract
        const BiswapBSWPoolAdapterBsc = await setupBscAdapterWithLib(
            "BiSwapFarmLPAdapterBsc",
            this.lib
        );
        this.adapter[1] = await BiswapBSWPoolAdapterBsc.deploy(
            0, // pid
            strategy,
            bsw,
            bsw,
            ethers.constants.AddressZero,
            biswapRouter,
            wbnb,
            "Biswap::Pool::BSW",
            this.authority.address
        );
        await this.adapter[1].deployed();

        // register path to pathFinder contract
        await setPath(this.pathFinder, this.pathManager, biswapRouter, [
            wbnb,
            bsw,
        ]);
        await setPath(this.pathFinder, this.pathManager, biswapRouter, [
            wbnb,
            usdt,
        ]);

        // add adapters to adapterList
        await this.adapterList
            .connect(this.adapterManager)
            .addAdapters([this.adapter[0].address, this.adapter[1].address]);

        // mint ybnft
        await mintNFT(
            this.ybNft,
            [this.adapter[0].address, this.adapter[1].address],
            [lpToken, bsw],
            this.performanceFee
        );

        this.checkAccRewardShare = async (tokenId) => {
            expect(
                BigNumber.from(
                    (await this.investor.tokenInfos(tokenId)).accRewardShare
                ).gt(BigNumber.from(this.accRewardShare))
            ).to.eq(true);

            this.accRewardShare = (
                await this.investor.tokenInfos(tokenId)
            ).accRewardShare;
        };

        console.log("Lib: ", this.lib.address);
        console.log("YBNFT: ", this.ybNft.address);
        console.log("Investor: ", this.investor.address);
        console.log("Authority: ", this.authority.address);
        console.log("AdapterList: ", this.adapterList.address);
        console.log("PathFinder: ", this.pathFinder.address);
        console.log("BiswapFarmLPAdapterBsc: ", this.adapter[0].address);
        console.log("BiswapBSWPoolAdapterBsc: ", this.adapter[1].address);
    });

    describe("deposit() function test", function () {
        it("(1) should be reverted when nft tokenId is invalid", async function () {
            // deposit to nftID: 3
            const depositAmount = ethers.utils.parseEther("1");
            await expect(
                this.investor.connect(this.alice).deposit(3, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2) should be reverted when amount is 0", async function () {
            // deposit to nftID: 1
            await expect(
                this.investor.deposit(1, {
                    gasPrice: 21e9,
                })
            ).to.be.revertedWith("Error: Insufficient BNB");
        });

        it("(3) deposit should success for Alice", async function () {
            const depositAmount = ethers.utils.parseEther("10");
            await expect(
                this.investor.connect(this.alice).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(
                    this.alice.address,
                    this.ybNft.address,
                    1,
                    depositAmount
                );

            const aliceInfo = await this.investor.userInfos(
                1,
                this.alice.address
            );
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(aliceInfo.amount).to.eq(BigNumber.from(10).mul(bnbPrice));
        });

        it("(4) deposit should success for Bob", async function () {
            // wait 40 mins
            for (let i = 0; i < 7200; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const beforeAdapterInfos = await this.investor.tokenInfos(1);
            const depositAmount = ethers.utils.parseEther("10");

            await expect(
                this.investor.connect(this.bob).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(
                    this.bob.address,
                    this.ybNft.address,
                    1,
                    depositAmount
                );

            await expect(
                this.investor.connect(this.bob).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(
                    this.bob.address,
                    this.ybNft.address,
                    1,
                    depositAmount
                );

            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.eq(BigNumber.from(20).mul(bnbPrice));

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            await this.checkAccRewardShare(1);
        });

        it("(5) test TVL & participants", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(
                BigNumber.from(30).mul(bnbPrice)
            ) &&
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

            await checkPendingWithClaim(
                this.investor,
                this.alice,
                1,
                this.performanceFee
            );
            await this.checkAccRewardShare(1);
        });

        it("(2) check withdrawable and claim for bob", async function () {
            await checkPendingWithClaim(
                this.investor,
                this.bob,
                1,
                this.performanceFee
            );
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
                    .connect(this.governor)
                    .withdraw(3, { gasPrice: 21e9 })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2) should receive the BNB successfully after withdraw function for Alice", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(
                this.alice.address
            );
            await expect(this.investor.connect(this.alice).withdraw(1)).to.emit(
                this.investor,
                "Withdrawn"
            );
            const afterBNB = await ethers.provider.getBalance(
                this.alice.address
            );
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            // check withdrawn balance
            expect(
                Number(
                    ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString())
                )
            ).to.be.gt(9.9);

            // check userInfo
            let aliceInfo = await this.investor.userInfos(
                1,
                this.alice.address
            );
            expect(aliceInfo.amount).to.eq(BigNumber.from(0));

            //------- check bob info -----//
            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.be.within(
                BigNumber.from(20).mul(bnbPrice).mul(99).div(100),
                BigNumber.from(20).mul(bnbPrice).mul(101).div(100)
            );

            await this.checkAccRewardShare(1);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.within(
                BigNumber.from(20).mul(bnbPrice).mul(99).div(100),
                BigNumber.from(20).mul(bnbPrice).mul(101).div(100)
            ) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "1"
                );
        });

        it("(4) should receive the BNB successfully after withdraw function for Bob", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(
                this.bob.address
            );

            await expect(this.investor.connect(this.bob).withdraw(1)).to.emit(
                this.investor,
                "Withdrawn"
            );

            const afterBNB = await ethers.provider.getBalance(this.bob.address);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            // check withdrawn balance
            expect(
                Number(
                    ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString())
                )
            ).to.be.gt(19.9);

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));

            await this.checkAccRewardShare(1);
        });

        it("(5) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq("0");
            expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                "0"
            );
        });
    });

    describe("pendingReward(), claim() function tests and protocol-fee test", function () {
        it("check if pendingReward is zero for new users", async function () {
            const pending = await this.investor.pendingReward(
                1,
                this.user1.address
            );

            expect(pending[0]).to.be.eq(0);
            expect(pending[1]).to.be.eq(0);
        });
        it("test with token1 and token2", async function () {
            await this.investor.connect(this.kyle).deposit(1, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("10"),
            });

            await this.investor.connect(this.jerry).deposit(2, {
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
            await this.investor.connect(this.alice).deposit(2, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("1"),
            });

            // check pending rewards
            await checkPendingWithClaim(
                this.investor,
                this.kyle,
                1,
                this.performanceFee
            );
            await checkPendingWithClaim(
                this.investor,
                this.jerry,
                2,
                this.performanceFee
            );

            // Successfully withdraw
            await expect(this.investor.connect(this.kyle).withdraw(1)).to.emit(
                this.investor,
                "Withdrawn"
            );

            await expect(this.investor.connect(this.jerry).withdraw(2)).to.emit(
                this.investor,
                "Withdrawn"
            );
        });
    });

    describe("Edit fund flow", function () {
        it("test possibility to set zero percent", async function () {
            await this.ybNft
                .connect(this.governor)
                .updateAllocations(1, [0, 10000]);
        });

        it("test with token1 and token2 - updateAllocations", async function () {
            await this.investor.connect(this.user1).deposit(1, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("10"),
            });

            await this.investor.connect(this.user2).deposit(2, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("100"),
            });

            // wait 40 mins
            for (let i = 0; i < 7200; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);
        });

        it("test pendingReward, invested amount ratio after allocation change", async function () {
            // Check reward increase after updateAllocation
            const allocation = [2000, 8000];
            const bTokenInfo1 = await this.adapter[0].userAdapterInfos(2);
            const bTokenInfo2 = await this.adapter[1].userAdapterInfos(2);
            const bPending1 = await this.investor.pendingReward(
                1,
                this.user1.address
            );
            const bPending2 = await this.investor.pendingReward(
                2,
                this.user2.address
            );

            await this.ybNft
                .connect(this.governor)
                .updateAllocations(2, allocation);

            // check pendingReward amount
            const aPending1 = await this.investor.pendingReward(
                1,
                this.user1.address
            );
            const aPending2 = await this.investor.pendingReward(
                2,
                this.user2.address
            );

            expect(aPending1[0]).gt(bPending1[0]) &&
                expect(aPending1[1]).gt(bPending1[1]);
            expect(aPending2[0]).gt(bPending2[0]) &&
                expect(aPending2[1]).gt(bPending2[1]);

            // check invested amount
            const aTokenInfo1 = await this.adapter[0].userAdapterInfos(2);
            const aTokenInfo2 = await this.adapter[1].userAdapterInfos(2);
            expect(BigNumber.from(bTokenInfo1.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo1.amount)
                    .div(allocation[0])
                    .mul(95)
                    .div(100)
            );
            expect(BigNumber.from(bTokenInfo2.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo2.amount)
                    .div(allocation[1])
                    .mul(95)
                    .div(100)
            );
        });

        it("test claimed rewards after allocation change", async function () {
            // Check pending reward by claim
            await checkPendingWithClaim(
                this.investor,
                this.user1,
                1,
                this.performanceFee
            );
            await checkPendingWithClaim(
                this.investor,
                this.user2,
                2,
                this.performanceFee
            );
        });

        it("test withdraw after allocation change", async function () {
            // Successfully withdraw
            await expect(this.investor.connect(this.user1).withdraw(1)).to.emit(
                this.investor,
                "Withdrawn"
            );
            await expect(this.investor.connect(this.user2).withdraw(2)).to.emit(
                this.investor,
                "Withdrawn"
            );
        });
    });
});
