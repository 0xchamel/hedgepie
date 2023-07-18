const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setPath, unlockAccount, forkBNBNetwork, checkPendingWithClaim } = require("../../../../shared/utilities");
const { setupHedgepie, setupBscAdapterWithLib, mintNFT } = require("../../../../shared/setup");

const BigNumber = ethers.BigNumber;

describe("RadiantV2 Adapters Integration Test", function () {
    before("Deploy contract", async function () {
        await forkBNBNetwork(28149870);

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
        [this.investor, this.authority, this.ybNft, this.adapterList, this.pathFinder, this.lib] = await setupHedgepie(
            this.governor,
            this.pathManager,
            this.adapterManager,
            this.treasury
        );

        const strategy = "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281"; // LendingPool
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address
        const name = "Radiant::Market::USDT";
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const USDT = "0x55d398326f99059fF775485246999027B3197955";
        const RDNT = "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF";
        const rUSDT = "0x4Ff2DD7c6435789E0BB56B0553142Ad00878a004"; // repayToken
        const compounder = "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367"; // Radiant compounder
        this.rewarderAddr = "0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa";
        this.rewarder = await unlockAccount(this.rewarderAddr);
        this.rewardReceiver = strategy;
        this.usdtToken = await ethers.getContractAt("IERC20", USDT);

        this.performanceFee = 500;
        this.accRewardShare = BigNumber.from(0);

        // Deploy RadiantV2AdapterBsc contract
        const RadiantV2AdapterBsc = await setupBscAdapterWithLib("RadiantV2Bsc", this.lib);
        this.adapter = [0, 0];
        this.adapter[0] = await RadiantV2AdapterBsc.deploy();
        await this.adapter[0].deployed();
        await this.adapter[0].initialize(
            strategy,
            USDT,
            RDNT,
            rUSDT,
            swapRouter,
            compounder,
            name,
            this.authority.address
        );

        // Deploy PancakeStakeAdapterBsc contract
        const PancakeStakeAdapterBsc = await setupBscAdapterWithLib("PancakeStakeAdapterBsc", this.lib);

        this.bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
        this.strategy = "0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3";
        this.stakingToken = "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82"; // CAKE
        this.rewardToken = "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd"; // SQUAD
        this.swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
        const cake = this.stakingToken;
        this.adapter[1] = await PancakeStakeAdapterBsc.deploy();
        await this.adapter[1].deployed();
        await this.adapter[1].initialize(
            this.strategy,
            this.stakingToken,
            this.rewardToken,
            this.swapRouter,
            "PK::STAKE::SQUAD-ADAPTER",
            this.authority.address
        );

        // register path to pathFinder contract
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, USDT]);
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, RDNT]);
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake]);
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake, this.rewardToken]);

        // add adapters to adapterList
        await this.adapterList
            .connect(this.adapterManager)
            .addAdapters([this.adapter[0].address, this.adapter[1].address]);
        await this.adapterList
            .connect(this.adapterManager)
            .addInfo(this.adapter[0].address, [name], [strategy], [0], [0], [0]);
        await this.adapterList
            .connect(this.adapterManager)
            .addInfo(
                this.adapter[1].address,
                ["PK::STAKE::SQUAD-ADAPTER"],
                ["0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3"],
                [0],
                [0],
                [0]
            );

        // mint ybnft
        await mintNFT(this.ybNft, [this.adapter[0].address, this.adapter[1].address], [0, 0], this.performanceFee);

        this.checkAccRewardShare = async (tokenId) => {
            expect(
                BigNumber.from((await this.investor.tokenInfos(tokenId)).accRewardShare).gte(
                    BigNumber.from(this.accRewardShare)
                )
            ).to.eq(true);

            this.accRewardShare = (await this.investor.tokenInfos(tokenId)).accRewardShare;
        };

        console.log("Lib: ", this.lib.address);
        console.log("YBNFT: ", this.ybNft.address);
        console.log("Investor: ", this.investor.address);
        console.log("Authority: ", this.authority.address);
        console.log("AdapterList: ", this.adapterList.address);
        console.log("PathFinder: ", this.pathFinder.address);
        console.log("RadiantMarketAdapterBsc: ", this.adapter[0].address);
        console.log("PancakeStakeAdapterBsc: ", this.adapter[1].address);
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
                .withArgs(this.alice.address, this.ybNft.address, 1, depositAmount);

            const aliceInfo = await this.investor.userInfos(1, this.alice.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(aliceInfo.amount).to.gte(BigNumber.from(10).mul(bnbPrice).mul(98).div(100));

            const profitInfo = (await this.ybNft.tokenInfos(1)).profit;
            expect(profitInfo).to.be.eq(0);
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
                .withArgs(this.bob.address, this.ybNft.address, 1, depositAmount);

            await expect(
                this.investor.connect(this.bob).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(this.bob.address, this.ybNft.address, 1, depositAmount);

            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());

            expect(bobInfo.amount).to.gt(BigNumber.from(20).mul(bnbPrice).mul(98).div(100));

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(BigNumber.from(afterAdapterInfos.totalStaked).gt(beforeAdapterInfos.totalStaked)).to.eq(true);

            await this.checkAccRewardShare(1);

            // check profit
            const profitInfo = (await this.ybNft.tokenInfos(1)).profit;
            expect(profitInfo).to.be.gte(0);

            const alicePending = await this.investor.pendingReward(1, this.alice.address);
            expect(profitInfo).to.be.within(
                alicePending.withdrawable.mul(99).div(100),
                alicePending.withdrawable.mul(101).div(100)
            );
        });

        it("(5) test TVL & participants", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.gt(
                BigNumber.from(30).mul(bnbPrice).mul(98).div(100)
            ) && expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("2");
        });
    });

    describe("claim() function test", function () {
        it("(1) check withdrawable and claim for alice", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            // wait 1 day
            for (let i = 0; i < 1800; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const userPending = await this.investor.pendingReward(1, this.alice.address);
            if (userPending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.alice, 1, this.performanceFee);
            }

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);

            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gte(bobPending);
        });

        it("(2) check withdrawable and claim for bob", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            const userPending = await this.investor.pendingReward(1, this.bob.address);
            if (userPending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.bob, 1, this.performanceFee);
            }

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);
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
            await expect(this.investor.connect(this.governor).withdraw(3, { gasPrice: 21e9 })).to.be.revertedWith(
                "Error: nft tokenId is invalid"
            );
        });

        it("(2) should receive the BNB successfully after withdraw function for Alice", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;
            const beforeBNB = await ethers.provider.getBalance(this.alice.address);
            await expect(this.investor.connect(this.alice).withdraw(1)).to.emit(this.investor, "Withdrawn");
            const afterBNB = await ethers.provider.getBalance(this.alice.address);
            expect(BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))).to.eq(true);

            // check withdrawn balance
            expect(Number(ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString()))).to.be.gt(9.9);

            // check userInfo
            let aliceInfo = await this.investor.userInfos(1, this.alice.address);
            expect(aliceInfo.amount).to.eq(BigNumber.from(0));

            //------- check bob info -----//
            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.gt(BigNumber.from(20).mul(bnbPrice).mul(98).div(100));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gte(bobPending);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.gt(
                BigNumber.from(20).mul(bnbPrice).mul(98).div(100)
            ) && expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("1");
        });

        it("(4) should receive the BNB successfully after withdraw function for Bob", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;
            const beforeBNB = await ethers.provider.getBalance(this.bob.address);

            await expect(this.investor.connect(this.bob).withdraw(1)).to.emit(this.investor, "Withdrawn");

            const afterBNB = await ethers.provider.getBalance(this.bob.address);
            expect(BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))).to.eq(true);

            // check withdrawn balance
            expect(afterBNB.sub(beforeBNB)).to.be.within(
                ethers.utils.parseEther("19.9").mul(99).div(1e2),
                ethers.utils.parseEther("19.9").mul(101).div(1e2)
            );

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);
        });

        it("(5) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq("0");
            expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("0");
        });
    });

    describe("pendingReward(), claim() function tests and protocol-fee test", function () {
        it("check if pendingReward is zero for new users", async function () {
            const pending = await this.investor.pendingReward(1, this.user1.address);

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
            const kylePending = await this.investor.pendingReward(1, this.kyle.address);
            if (kylePending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.kyle, 1, this.performanceFee);
            }

            const jerryPending = await this.investor.pendingReward(1, this.jerry.address);
            if (jerryPending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.jerry, 2, this.performanceFee);
            }

            // Successfully withdraw
            await expect(this.investor.connect(this.kyle).withdraw(1)).to.emit(this.investor, "Withdrawn");

            await expect(this.investor.connect(this.jerry).withdraw(2)).to.emit(this.investor, "Withdrawn");
        });
    });

    describe("Edit fund flow", function () {
        it("test possibility to set zero percent", async function () {
            await this.ybNft.connect(this.governor).updateAllocations(1, [
                [0, this.adapter[0].address, 0],
                [10000, this.adapter[1].address, 0],
            ]);
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
            const allocation = [
                [2000, this.adapter[0].address, 0],
                [8000, this.adapter[1].address, 0],
            ];
            const bTokenInfo1 = await this.adapter[0].userAdapterInfos(2, 0);
            const bTokenInfo2 = await this.adapter[1].userAdapterInfos(2, 0);
            const bPending1 = await this.investor.pendingReward(1, this.user1.address);
            const bPending2 = await this.investor.pendingReward(2, this.user2.address);
            await this.ybNft.connect(this.governor).updateAllocations(2, allocation);

            // check pendingReward amount
            const aPending1 = await this.investor.pendingReward(1, this.user1.address);
            const aPending2 = await this.investor.pendingReward(2, this.user2.address);
            expect(aPending1[0]).gte(bPending1[0]) && expect(aPending1[1]).gte(bPending1[1]);
            expect(aPending2[0]).gte(bPending2[0]) && expect(aPending2[1]).gte(bPending2[1]);

            // check invested amount
            const aTokenInfo1 = await this.adapter[0].userAdapterInfos(2, 0);
            const aTokenInfo2 = await this.adapter[1].userAdapterInfos(2, 0);
            expect(BigNumber.from(bTokenInfo1.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo1.amount).div(allocation[0][0]).mul(95).div(100)
            );
            expect(BigNumber.from(bTokenInfo2.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo2.amount).div(allocation[1][0]).mul(95).div(100)
            );
        });

        it("test claimed rewards after allocation change", async function () {
            // Check pending reward by claim
            const user1Pending = await this.investor.pendingReward(1, this.user1.address);
            if (user1Pending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.user1, 1, this.performanceFee);
            }

            const user2Pending = await this.investor.pendingReward(1, this.user2.address);
            if (user2Pending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.user2, 2, this.performanceFee);
            }
        });

        it("test withdraw after allocation change", async function () {
            // Successfully withdraw
            await expect(this.investor.connect(this.user1).withdraw(1)).to.emit(this.investor, "Withdrawn");
            await expect(this.investor.connect(this.user2).withdraw(2)).to.emit(this.investor, "Withdrawn");
        });
    });

    describe("deposit() function test after edit fund", function () {
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
                .withArgs(this.alice.address, this.ybNft.address, 1, depositAmount);

            const aliceInfo = await this.investor.userInfos(1, this.alice.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(aliceInfo.amount).to.gt(BigNumber.from(10).mul(bnbPrice).mul(98).div(100));
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
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            await expect(
                this.investor.connect(this.bob).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(this.bob.address, this.ybNft.address, 1, depositAmount);

            await expect(
                this.investor.connect(this.bob).deposit(1, {
                    gasPrice: 21e9,
                    value: depositAmount,
                })
            )
                .to.emit(this.investor, "Deposited")
                .withArgs(this.bob.address, this.ybNft.address, 1, depositAmount);

            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.eq(BigNumber.from(20).mul(bnbPrice));

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(BigNumber.from(afterAdapterInfos.totalStaked).gt(beforeAdapterInfos.totalStaked)).to.eq(true);

            await this.checkAccRewardShare(1);

            // check profit
            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const alicePending = await this.investor.pendingReward(1, this.alice.address);
            expect(afterProfit.sub(beforeProfit)).to.be.within(
                alicePending.withdrawable.mul(99).div(100),
                alicePending.withdrawable.mul(101).div(100)
            );
        });

        it("(5) test TVL & participants", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.gt(
                BigNumber.from(30).mul(bnbPrice).mul(98).div(100)
            ) && expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("2");
        });
    });

    describe("claim() function test after edit fund", function () {
        it("(1) check withdrawable and claim for alice", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            // wait 1 day
            for (let i = 0; i < 1800; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            const alicePending = await this.investor.pendingReward(1, this.alice.address);
            if (alicePending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.alice, 1, this.performanceFee);
            }
            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);

            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gte(bobPending);
        });

        it("(2) check withdrawable and claim for bob", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            const bobPending = await this.investor.pendingReward(1, this.bob.address);
            if (bobPending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.bob, 1, this.performanceFee);
            }

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);
        });
    });

    describe("withdrawBNB() function test after edit fund", function () {
        it("(1) revert when nft tokenId is invalid", async function () {
            for (let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            // withdraw to nftID: 3
            await expect(this.investor.connect(this.governor).withdraw(3, { gasPrice: 21e9 })).to.be.revertedWith(
                "Error: nft tokenId is invalid"
            );
        });

        it("(2) should receive the BNB successfully after withdraw function for Alice", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;
            const beforeBNB = await ethers.provider.getBalance(this.alice.address);
            await expect(this.investor.connect(this.alice).withdraw(1)).to.emit(this.investor, "Withdrawn");
            const afterBNB = await ethers.provider.getBalance(this.alice.address);
            expect(BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))).to.eq(true);

            // check withdrawn balance
            expect(Number(ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString()))).to.be.gt(9.9);

            // check userInfo
            let aliceInfo = await this.investor.userInfos(1, this.alice.address);
            expect(aliceInfo.amount).to.eq(BigNumber.from(0));

            //------- check bob info -----//
            const bobInfo = await this.investor.userInfos(1, this.bob.address);
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.gt(BigNumber.from(20).mul(bnbPrice).mul(98).div(100));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gte(bobPending);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.gt(
                BigNumber.from(20).mul(bnbPrice).mul(98).div(100)
            ) && expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("1");
        });

        it("(4) should receive the BNB successfully after withdraw function for Bob", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(this.bob.address);
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            await expect(this.investor.connect(this.bob).withdraw(1)).to.emit(this.investor, "Withdrawn");

            const afterBNB = await ethers.provider.getBalance(this.bob.address);
            expect(BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))).to.eq(true);

            // check withdrawn balance
            expect(Number(ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString()))).to.be.gt(19.8);

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);
        });

        it("(5) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq("0");
            expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("0");
        });
    });

    describe("pendingReward(), claim() function tests and protocol-fee test after edit fund", function () {
        it("check if pendingReward is zero for new users", async function () {
            const pending = await this.investor.pendingReward(1, this.user1.address);

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

            let beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

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
            const kylePending = await this.investor.pendingReward(1, this.kyle.address);
            if (kylePending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.kyle, 1, this.performanceFee);
            }
            const jerryPending = await this.investor.pendingReward(1, this.jerry.address);
            if (jerryPending.withdrawable.gt(0)) {
                await checkPendingWithClaim(this.investor, this.ybNft, this.jerry, 2, this.performanceFee);
            }

            let afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);

            beforeProfit = afterProfit;

            // Successfully withdraw
            await expect(this.investor.connect(this.kyle).withdraw(1)).to.emit(this.investor, "Withdrawn");

            await expect(this.investor.connect(this.jerry).withdraw(2)).to.emit(this.investor, "Withdrawn");

            afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gte(beforeProfit);
        });
    });
});
