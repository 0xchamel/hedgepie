const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setPath, checkPendingWithClaim, forkBNBNetwork } = require("../../../../shared/utilities");
const { setupHedgepie, setupBscAdapterWithLib, mintNFT } = require("../../../../shared/setup");

const BigNumber = ethers.BigNumber;

describe("Belt Adapters Integration Test", function () {
    before("Deploy contract", async function () {
        await forkBNBNetwork();

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

        const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
        const USDT = "0x55d398326f99059fF775485246999027B3197955";
        const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const stakingToken = BUSD; // BUSD
        const strategy = "0x9171Bf7c050aC8B4cf7835e51F7b4841DFB2cCD0"; // beltBUSD
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address
        const name = "Belt::Vault::BUSD";

        this.rewarder = "0x4ecca0a9649329628b77a7d213eacdd5b3431f73"; // bAutoBUSD
        this.ctRewarder = await ethers.getContractAt("IERC20", this.rewarder);
        this.performanceFee = 500;
        this.accRewardShare = BigNumber.from(0);

        // Deploy BeltVaultAdapterBsc contract
        const BeltVaultAdapter = await setupBscAdapterWithLib("BeltVaultAdapterBsc", this.lib);
        this.adapter = [0, 0];
        this.adapter[0] = await BeltVaultAdapter.deploy(
            strategy,
            stakingToken,
            strategy,
            swapRouter,
            name,
            this.authority.address
        );
        await this.adapter[0].deployed();

        // Deploy PancakeStakeAdapterBsc contract
        const PancakeStakeAdapterBsc = await setupBscAdapterWithLib("PancakeStakeAdapterBsc", this.lib);

        this.bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
        this.strategy = "0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3";
        this.stakingToken = "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82"; // CAKE
        this.rewardToken = "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd"; // SQUAD
        this.swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
        this.adapter[1] = await PancakeStakeAdapterBsc.deploy(
            this.strategy,
            this.stakingToken,
            this.rewardToken,
            this.swapRouter,
            "PK::STAKE::SQUAD-ADAPTER",
            this.authority.address
        );

        await this.adapter[1].deployed();

        // register path to pathFinder contract
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake]);
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake, this.rewardToken]);
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, USDT]);
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, BUSD]);

        // add adapters to adapterList
        await this.adapterList
            .connect(this.adapterManager)
            .addAdapters([this.adapter[0].address, this.adapter[1].address]);

        // mint ybnft
        await mintNFT(this.ybNft, [this.adapter[0].address, this.adapter[1].address], this.performanceFee);

        this.checkAccRewardShare = async (tokenId) => {
            expect(
                BigNumber.from((await this.investor.tokenInfos(tokenId)).accRewardShare).gt(
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
        console.log("BeltVaultAdapterBsc: ", this.adapter[0].address);
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
            expect(aliceInfo.amount).to.gt(0);

            const profitInfo = (await this.ybNft.tokenInfos(1)).profit;
            expect(profitInfo).to.be.eq(0);
        });

        it("(4) deposit should success for Bob", async function () {
            // wait 6 hrs
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
            expect(bobInfo.amount).to.gt(0);

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(BigNumber.from(afterAdapterInfos.totalStaked).gt(beforeAdapterInfos.totalStaked)).to.eq(true);

            await this.checkAccRewardShare(1);

            // check profit
            const profitInfo = (await this.ybNft.tokenInfos(1)).profit;
            expect(profitInfo).to.be.gt(0);

            const alicePending = await this.investor.pendingReward(1, this.alice.address);
            expect(profitInfo).to.be.within(
                alicePending.withdrawable.mul(99).div(100),
                alicePending.withdrawable.mul(101).div(100)
            );
        });

        it("(5) test TVL & participants", async function () {
            const aliceInfo = await this.investor.userInfos(1, this.alice.address);
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(
                BigNumber.from(aliceInfo.amount).add(BigNumber.from(bobInfo.amount))
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

            await checkPendingWithClaim(this.investor, this.ybNft, this.alice, 1, this.performanceFee);
            await this.checkAccRewardShare(1);

            // check profit
            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);

            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gt(bobPending);
        });

        it("(2) check withdrawable and claim for bob", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            await checkPendingWithClaim(this.investor, this.ybNft, this.bob, 1, this.performanceFee);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);
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
            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.gt(0);

            await this.checkAccRewardShare(1);

            // check profit
            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gt(bobPending);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(BigNumber.from(bobInfo.amount)) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("1");
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
            expect(Number(ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString()))).to.be.gt(19.8);

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);
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

            // wait 6 hrs
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
            await checkPendingWithClaim(this.investor, this.ybNft, this.kyle, 1, this.performanceFee);
            await checkPendingWithClaim(this.investor, this.ybNft, this.jerry, 2, this.performanceFee);

            // Successfully withdraw
            await expect(this.investor.connect(this.kyle).withdraw(1)).to.emit(this.investor, "Withdrawn");

            await expect(this.investor.connect(this.jerry).withdraw(2)).to.emit(this.investor, "Withdrawn");
        });
    });

    describe("Edit fund flow", function () {
        it("test possibility to set zero percent", async function () {
            await this.ybNft.connect(this.governor).updateAllocations(1, [
                [0, this.adapter[0].address],
                [10000, this.adapter[1].address],
            ]);
        });

        it("test with token1 and token2 - updateAllocations", async function () {
            await this.investor.connect(this.user1).deposit(1, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("10"),
            });

            await this.investor.connect(this.user2).deposit(2, {
                gasPrice: 21e9,
                value: ethers.utils.parseEther("20"),
            });

            // wait 6 hrs
            for (let i = 0; i < 7200; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);
        });

        it("test pendingReward, invested amount ratio after allocation change", async function () {
            // Check reward increase after updateAllocation
            const allocation = [
                [2000, this.adapter[0].address],
                [8000, this.adapter[1].address],
            ];
            const bTokenInfo1 = await this.adapter[0].userAdapterInfos(2);
            const bTokenInfo2 = await this.adapter[1].userAdapterInfos(2);
            const bPending1 = await this.investor.pendingReward(1, this.user1.address);
            const bPending2 = await this.investor.pendingReward(2, this.user2.address);
            await this.ybNft.connect(this.governor).updateAllocations(2, allocation);

            // check pendingReward amount
            const aPending1 = await this.investor.pendingReward(1, this.user1.address);
            const aPending2 = await this.investor.pendingReward(2, this.user2.address);

            expect(aPending1[0]).gt(bPending1[0]);
            expect(aPending2[0]).gt(bPending2[0]);

            // check invested amount
            const aTokenInfo1 = await this.adapter[0].userAdapterInfos(2);
            const aTokenInfo2 = await this.adapter[1].userAdapterInfos(2);
            expect(BigNumber.from(bTokenInfo1.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo1.amount).div(allocation[0][0]).mul(95).div(100)
            );
            expect(BigNumber.from(bTokenInfo2.amount).div(50)).to.be.gt(
                BigNumber.from(aTokenInfo2.amount).div(allocation[1][0]).mul(95).div(100)
            );
        });

        it("test claimed rewards after allocation change", async function () {
            // Check pending reward by claim
            await checkPendingWithClaim(this.investor, this.ybNft, this.user1, 1, this.performanceFee);
            await checkPendingWithClaim(this.investor, this.ybNft, this.user2, 2, this.performanceFee);
        });

        it("test withdraw after allocation change", async function () {
            // Successfully withdraw
            await expect(this.investor.connect(this.user1).withdraw(1)).to.emit(this.investor, "Withdrawn");
            await expect(this.investor.connect(this.user2).withdraw(2)).to.emit(this.investor, "Withdrawn");
        });
    });

    describe("deposit() function test after editFund", function () {
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
            expect(aliceInfo.amount).to.gt(0);

            // check profit
            const profitInfo = (await this.ybNft.tokenInfos(1)).profit;
            expect(profitInfo).to.be.gt(0);
        });

        it("(4) deposit should success for Bob", async function () {
            // wait 6 hrs
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
            expect(bobInfo.amount).to.gt(0);

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(BigNumber.from(afterAdapterInfos.totalStaked).gt(beforeAdapterInfos.totalStaked)).to.eq(true);

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const alicePending = await this.investor.pendingReward(1, this.alice.address);
            expect(afterProfit.sub(beforeProfit)).to.be.within(
                alicePending.withdrawable.mul(99).div(100),
                alicePending.withdrawable.mul(101).div(100)
            );
        });

        it("(5) test TVL & participants", async function () {
            const aliceInfo = await this.investor.userInfos(1, this.alice.address);
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(
                BigNumber.from(aliceInfo.amount).add(BigNumber.from(bobInfo.amount))
            ) && expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("2");
        });
    });

    describe("claim() function test after editFund", function () {
        it("(1) check withdrawable and claim for alice", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            // wait 1 day
            for (let i = 0; i < 1800; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24]);
            await ethers.provider.send("evm_mine", []);

            await checkPendingWithClaim(this.investor, this.ybNft, this.alice, 1, this.performanceFee);
            await this.checkAccRewardShare(1);

            // check profit
            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);

            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gt(bobPending);
        });

        it("(2) check withdrawable and claim for bob", async function () {
            const beforeProfit = (await this.ybNft.tokenInfos(1)).profit;

            await checkPendingWithClaim(this.investor, this.ybNft, this.bob, 1, this.performanceFee);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);
        });
    });

    describe("withdrawBNB() function test after editFund", function () {
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
            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(bobInfo.amount).to.gt(0);

            await this.checkAccRewardShare(1);

            // check profit
            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            const bobPending = (await this.investor.pendingReward(1, this.bob.address)).withdrawable;
            expect(afterProfit.sub(beforeProfit)).to.be.gt(bobPending);
        });

        it("(3) test TVL & participants after Alice withdraw", async function () {
            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(BigNumber.from(bobInfo.amount)) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("1");
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
            expect(Number(ethers.utils.formatEther(afterBNB.sub(beforeBNB).toString()))).to.be.gt(19.8);

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));

            await this.checkAccRewardShare(1);

            const afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);
        });

        it("(5) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq("0");
            expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq("0");
        });
    });

    describe("pendingReward(), claim() function tests and protocol-fee test after editFund", function () {
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

            // wait 6 hrs
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
            await checkPendingWithClaim(this.investor, this.ybNft, this.kyle, 1, this.performanceFee);
            await checkPendingWithClaim(this.investor, this.ybNft, this.jerry, 2, this.performanceFee);

            let afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);

            beforeProfit = afterProfit;

            // Successfully withdraw
            await expect(this.investor.connect(this.kyle).withdraw(1)).to.emit(this.investor, "Withdrawn");

            await expect(this.investor.connect(this.jerry).withdraw(2)).to.emit(this.investor, "Withdrawn");

            afterProfit = (await this.ybNft.tokenInfos(1)).profit;
            expect(afterProfit).to.be.gt(beforeProfit);
        });
    });
});
