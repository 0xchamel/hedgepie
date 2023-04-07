const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setPath, encode } = require("../../../../shared/utilities");
const {
    setupHedgepie,
    setupBscAdapterWithLib,
    mintNFT,
} = require("../../../../shared/setup");

const BigNumber = ethers.BigNumber;

describe("Multiple Adapters Integration Test", function () {
    const checkPendingWithClaim = async (
        investor,
        user,
        tokenId,
        performanceFee
    ) => {
        const userPending = await investor.pendingReward(tokenId, user.address);
        expect(userPending.withdrawable).gt(0);

        const estimatePending = BigNumber.from(userPending.withdrawable)
            .mul(1e4 - performanceFee)
            .div(1e4);

        const beforeBNB = await ethers.provider.getBalance(user.address);

        const claimTx = await investor.connect(user).claim(tokenId);
        const claimTxResp = await claimTx.wait();
        const gasAmt = BigNumber.from(claimTxResp.effectiveGasPrice).mul(
            BigNumber.from(claimTxResp.gasUsed)
        );

        const afterBNB = await ethers.provider.getBalance(user.address);
        const actualPending = BigNumber.from(afterBNB)
            .add(gasAmt)
            .sub(beforeBNB);

        // actualPending in 2% range of estimatePending
        expect(actualPending).gte(estimatePending.mul(98).div(1e2));
    };

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

        const bsw = "0x965f527d9159dce6288a2219db51fc6eef120dd1";
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
        const usdt = "0x55d398326f99059ff775485246999027b3197955";
        const busd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

        const pksRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
        const biswapRouter = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8";

        this.performanceFee = 500;
        this.accRewardShare = BigNumber.from(0);

        this.adapter = [0, 0, 0, 0, 0, 0, 0];

        // Deploy PancakeSwapFarmLPAdapterBsc contract
        const pksMasterChef = "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652"; // MasterChef v2 pks
        const pksLpToken = "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0"; // WBNB-CAKE LP
        const PancakeSwapFarmLPAdapterBsc = await setupBscAdapterWithLib(
            "PancakeSwapFarmLPAdapterBsc",
            this.lib
        );
        this.adapter[0] = await PancakeSwapFarmLPAdapterBsc.deploy(
            2, // pid
            pksMasterChef,
            pksLpToken,
            cake,
            pksRouter,
            wbnb,
            "PancakeSwap::Farm::CAKE-WBNB",
            this.authority.address
        );
        await this.adapter[0].deployed();

        // Deploy PancakeStakeAdapterBsc contract
        const pksStakeStrategy = "0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3";
        const pksStakeReward = "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd"; // SQUAD
        const PancakeStakeAdapterBsc = await setupBscAdapterWithLib(
            "PancakeStakeAdapterBsc",
            this.lib
        );
        this.adapter[1] = await PancakeStakeAdapterBsc.deploy(
            pksStakeStrategy,
            cake,
            pksStakeReward,
            pksRouter,
            wbnb,
            "PK::STAKE::SQUAD-ADAPTER",
            this.authority.address
        );
        await this.adapter[1].deployed();

        // Deploy BiswapFarmLPAdapterBsc contract
        const biswapStrategy = "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739"; // MasterChef Biswap
        const biswapLpToken = "0x2b30c317ceDFb554Ec525F85E79538D59970BEb0"; // USDT-BSW LP
        const BiswapFarmLPAdapterBsc = await setupBscAdapterWithLib(
            "BiSwapFarmLPAdapterBsc",
            this.lib
        );
        this.adapter[2] = await BiswapFarmLPAdapterBsc.deploy(
            9, // pid
            biswapStrategy,
            biswapLpToken,
            bsw,
            biswapRouter,
            biswapRouter,
            wbnb,
            "Biswap::Farm::USDT-BSW",
            this.authority.address
        );
        await this.adapter[2].deployed();

        // Deploy BiswapBSWPoolAdapterBsc contract
        const BiswapBSWPoolAdapterBsc = await setupBscAdapterWithLib(
            "BiSwapFarmLPAdapterBsc",
            this.lib
        );
        this.adapter[3] = await BiswapBSWPoolAdapterBsc.deploy(
            0, // pid
            biswapStrategy,
            bsw,
            bsw,
            ethers.constants.AddressZero,
            biswapRouter,
            wbnb,
            "Biswap::Pool::BSW",
            this.authority.address
        );
        await this.adapter[3].deployed();

        // Deploy AutoVaultAdapterBsc contract
        const autofarmStrategy = "0x0895196562C7868C5Be92459FaE7f877ED450452"; // MasterChef
        const autofarmVStrategy = "0xcFF7815e0e85a447b0C21C94D25434d1D0F718D1"; // vStrategy of vault
        const autofarmStaking = "0x0ed7e52944161450477ee417de9cd3a859b14fd0"; // WBNB-Cake LP
        const AutoFarmAdapter = await setupBscAdapterWithLib(
            "AutoVaultAdapterBsc",
            this.lib
        );
        this.adapter[4] = await AutoFarmAdapter.deploy(
            619,
            autofarmStrategy,
            autofarmVStrategy,
            autofarmStaking,
            pksRouter,
            pksRouter,
            wbnb,
            "AutoFarm::Vault::WBNB-CAKE",
            this.authority.address
        );
        await this.adapter[4].deployed();

        // Deploy BeltVaultAdapterBsc contract
        const beltStrategy = "0x9171Bf7c050aC8B4cf7835e51F7b4841DFB2cCD0"; // beltBUSD
        const BeltVaultAdapter = await setupBscAdapterWithLib(
            "BeltVaultAdapterBsc",
            this.lib
        );
        this.adapter[5] = await BeltVaultAdapter.deploy(
            beltStrategy,
            busd,
            beltStrategy,
            pksRouter,
            wbnb,
            "Belt::Vault::BUSD",
            this.authority.address
        );
        await this.adapter[5].deployed();

        // Deploy BeefyVaultAdapterBsc contract
        const beefyStrategy = "0x164fb78cAf2730eFD63380c2a645c32eBa1C52bc"; // Moo BiSwap USDT-BUSD
        const beefyStaking = "0xDA8ceb724A06819c0A5cDb4304ea0cB27F8304cF"; // Biswap USDT-BUSD LP
        const BeefyVaultAdapter = await setupBscAdapterWithLib(
            "BeefyVaultAdapterBsc",
            this.lib
        );
        this.adapter[6] = await BeefyVaultAdapter.deploy(
            beefyStrategy,
            beefyStaking,
            biswapRouter,
            pksRouter,
            wbnb,
            "Beefy::Vault::Biswap USDT-BUSD",
            this.authority.address
        );
        await this.adapter[6].deployed();

        // setPath for PKS adapters
        await setPath(this.pathFinder, this.pathManager, pksRouter, [
            wbnb,
            cake,
        ]);
        await setPath(this.pathFinder, this.pathManager, pksRouter, [
            wbnb,
            cake,
            pksStakeReward,
        ]);

        // setPath for biswap adapters
        await setPath(this.pathFinder, this.pathManager, biswapRouter, [
            wbnb,
            bsw,
        ]);
        await setPath(this.pathFinder, this.pathManager, biswapRouter, [
            wbnb,
            usdt,
        ]);

        // register path to pathFinder contract
        await setPath(this.pathFinder, this.pathManager, biswapRouter, [
            wbnb,
            busd,
        ]);
        await setPath(this.pathFinder, this.pathManager, pksRouter, [
            wbnb,
            usdt,
        ]);
        await setPath(this.pathFinder, this.pathManager, pksRouter, [
            wbnb,
            busd,
        ]);

        // add adapters to adapterList
        await this.adapterList
            .connect(this.adapterManager)
            .addAdapters([
                this.adapter[0].address,
                this.adapter[1].address,
                this.adapter[2].address,
                this.adapter[3].address,
                this.adapter[4].address,
                this.adapter[5].address,
                this.adapter[6].address,
            ]);

        // mint ybnft
        await this.ybNft.mint(
            [1500, 1500, 1500, 1500, 1500, 2500, 0],
            [
                pksLpToken,
                cake,
                biswapLpToken,
                bsw,
                autofarmStaking,
                busd,
                beefyStaking,
            ],
            [
                this.adapter[0].address,
                this.adapter[1].address,
                this.adapter[2].address,
                this.adapter[3].address,
                this.adapter[4].address,
                this.adapter[5].address,
                this.adapter[6].address,
            ],
            this.performanceFee,
            "test tokenURI1"
        );

        await this.ybNft.mint(
            [1000, 1500, 1500, 1500, 1500, 3000, 0],
            [
                pksLpToken,
                cake,
                biswapLpToken,
                bsw,
                autofarmStaking,
                busd,
                beefyStaking,
            ],
            [
                this.adapter[0].address,
                this.adapter[1].address,
                this.adapter[2].address,
                this.adapter[3].address,
                this.adapter[4].address,
                this.adapter[5].address,
                this.adapter[6].address,
            ],
            this.performanceFee,
            "test tokenURI2"
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
        console.log("PKSLPFarmAdapterBsc: ", this.adapter[0].address);
        console.log("PKSStakeAdapterBsc: ", this.adapter[1].address);
        console.log("BiswapLPFarmAdapterBsc: ", this.adapter[2].address);
        console.log("BiswapBSWAdapterBsc: ", this.adapter[3].address);
        console.log("AutofarmVaultAdapterBsc: ", this.adapter[4].address);
        console.log("BeltVaultAdapterBsc: ", this.adapter[5].address);
        console.log("BeefyVaultAdapterBsc: ", this.adapter[6].address);
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
            expect(aliceInfo.amount).to.gt(0);
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
            expect(bobInfo.amount).to.gt(0);

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            await this.checkAccRewardShare(1);
        });

        it("(5) test TVL & participants", async function () {
            const aliceInfo = await this.investor.userInfos(
                1,
                this.alice.address
            );
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(
                BigNumber.from(aliceInfo.amount).add(
                    BigNumber.from(bobInfo.amount)
                )
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
            const nftInfo = await this.ybNft.tokenInfos(1);

            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
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
            ).to.be.gt(19.8);

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

    describe("Edit fund flow", function () {
        it("test possibility to set zero percent", async function () {
            await this.ybNft
                .connect(this.governor)
                .updateAllocations(1, [0, 0, 0, 0, 0, 10000, 0]);
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
            const allocation = [2000, 1000, 1000, 2000, 2000, 2000, 0];
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
            expect(aPending1[0]).gte(bPending1[0]) &&
                expect(aPending1[1]).gte(bPending1[1]);
            expect(aPending2[0]).gte(bPending2[0]) &&
                expect(aPending2[1]).gte(bPending2[1]);

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

    describe("deposit() function test after editFund", function () {
        it("(1) deposit should success for Alice", async function () {
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
            expect(aliceInfo.amount).to.gt(0);
        });

        it("(2) deposit should success for Bob", async function () {
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
            expect(bobInfo.amount).to.gt(0);

            const afterAdapterInfos = await this.investor.tokenInfos(1);
            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            await this.checkAccRewardShare(1);
        });

        it("(3) test TVL & participants", async function () {
            const aliceInfo = await this.investor.userInfos(
                1,
                this.alice.address
            );
            const bobInfo = await this.investor.userInfos(1, this.bob.address);

            // const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq(
                BigNumber.from(aliceInfo.amount).add(
                    BigNumber.from(bobInfo.amount)
                )
            ) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "2"
                );
        });
    });

    describe("claim() function test after editFund", function () {
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

    describe("withdrawBNB() function test after editFund", function () {
        it("(1) should receive the BNB successfully after withdraw function for Alice", async function () {
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
        });

        it("(2) test TVL & participants after Alice withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            const bnbPrice = BigNumber.from(await this.lib.getBNBPrice());
            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.within(
                BigNumber.from(20).mul(bnbPrice).mul(99).div(100),
                BigNumber.from(20).mul(bnbPrice).mul(101).div(100)
            ) &&
                expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                    "1"
                );
        });

        it("(3) should receive the BNB successfully after withdraw function for Bob", async function () {
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
            ).to.be.gt(19.9 * 0.99);

            let bobInfo = await this.investor.userInfos(1, this.bob.address);
            expect(bobInfo.amount).to.eq(BigNumber.from(0));
        });

        it("(4) test TVL & participants after Alice & Bob withdraw", async function () {
            const nftInfo = await this.ybNft.tokenInfos(1);

            expect(BigNumber.from(nftInfo.tvl).toString()).to.be.eq("0");
            expect(BigNumber.from(nftInfo.participant).toString()).to.be.eq(
                "0"
            );
        });
    });
});
