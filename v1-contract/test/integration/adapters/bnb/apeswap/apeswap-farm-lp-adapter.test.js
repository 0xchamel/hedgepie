const { expect } = require("chai");
const { ethers } = require("hardhat");
const { setPath } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

describe("ApeswapFarmLPAdapter Integration Test", function () {
    before("Deploy contract", async function () {
        const [owner, alice, bob, treasury, kyle, jerry] =
            await ethers.getSigners();

        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
        const Banana = "0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95";
        const strategy = "0x5c8D727b265DBAfaba67E050f2f739cAeEB4A6F9"; // MasterApe
        const lpToken = "0x51e6D27FA57373d8d4C256231241053a70Cb1d93"; // BUSD-WBNB LP
        const apeRouter = "0xcF0feBd3f17CEf5b47b0cD257aCf6025c5BFf3b7";

        this.owner = owner;
        this.alice = alice;
        this.bob = bob;
        this.kyle = kyle;
        this.jerry = jerry;
        this.performanceFee = 100;

        this.bobAddr = bob.address;
        this.aliceAddr = alice.address;
        this.treasuryAddr = treasury.address;

        this.accTokenPerShare = BigNumber.from(0);
        this.accTokenPerShare1 = BigNumber.from(0);

        // Deploy Apeswap LP Adapter contract
        const ApeLPAdapter = await adapterFixtureBsc("ApeswapFarmLPAdapter");
        this.aAdapter = await ApeLPAdapter.deploy(
            3, // pid
            strategy,
            lpToken,
            Banana,
            apeRouter,
            wbnb,
            "Apeswap::Farm::BUSD-WBNB"
        );
        await this.aAdapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.aAdapter,
                treasury.address,
                lpToken,
                this.performanceFee
            );

        // Set investor in vAdapter
        await setPath(this.aAdapter, wbnb, BUSD);
        await setPath(this.aAdapter, wbnb, Banana);

        console.log("Owner: ", this.owner.address);
        console.log("Investor: ", this.investor.address);
        console.log("Strategy: ", strategy);
        console.log("ApeswapFarmLPAdapter: ", this.aAdapter.address);
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
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            expect(Number(aliceInfo) / Math.pow(10, 18)).to.eq(10);

            const aliceAdapterInfos = await this.aAdapter.userAdapterInfos(
                this.aliceAddr,
                1
            );
            const adapterInfos = await this.aAdapter.mAdapter();
            expect(BigNumber.from(adapterInfos.totalStaked)).to.eq(
                BigNumber.from(aliceAdapterInfos.amount)
            );

            // Check accTokenPerShare Info
            this.accTokenPerShare = (
                await this.aAdapter.mAdapter()
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

            const beforeAdapterInfos = await this.aAdapter.mAdapter();
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
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            expect(Number(bobInfo) / Math.pow(10, 18)).to.eq(20);

            const bobAdapterInfos = await this.aAdapter.userAdapterInfos(
                this.bobAddr,
                1
            );
            expect(BigNumber.from(bobAdapterInfos.amount).gt(0)).to.eq(true);

            const afterAdapterInfos = await this.aAdapter.mAdapter();

            expect(
                BigNumber.from(afterAdapterInfos.totalStaked).gt(
                    beforeAdapterInfos.totalStaked
                )
            ).to.eq(true);

            // Check accTokenPerShare Info
            expect(
                BigNumber.from(
                    (await this.aAdapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.aAdapter.mAdapter()
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
            for (let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(this.aliceAddr);
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let aliceInfo = (
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;

            await expect(
                this.investor.connect(this.alice).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.aliceAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            aliceInfo = (
                await this.aAdapter.userAdapterInfos(this.aliceAddr, 1)
            ).invested;
            expect(aliceInfo).to.eq(BigNumber.from(0));

            const bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;
            const bobDeposit = Number(bobInfo) / Math.pow(10, 18);
            expect(bobDeposit).to.eq(20);

            expect(
                BigNumber.from(
                    (await this.aAdapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.aAdapter.mAdapter()
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
            for (let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine", []);
            }
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 30]);
            await ethers.provider.send("evm_mine", []);

            // withdraw from nftId: 1
            const beforeBNB = await ethers.provider.getBalance(this.bobAddr);
            const beforeOwnerBNB = await ethers.provider.getBalance(
                this.treasuryAddr
            );
            let bobInfo = (
                await this.aAdapter.userAdapterInfos(this.bobAddr, 1)
            ).invested;

            await expect(
                this.investor.connect(this.bob).withdrawBNB(1)
            ).to.emit(this.investor, "WithdrawBNB");

            const afterBNB = await ethers.provider.getBalance(this.bobAddr);
            expect(
                BigNumber.from(afterBNB).gt(BigNumber.from(beforeBNB))
            ).to.eq(true);

            bobInfo = (await this.aAdapter.userAdapterInfos(this.bobAddr, 1))
                .invested;
            expect(bobInfo).to.eq(BigNumber.from(0));

            // Check accTokenPerShare Info
            expect(
                BigNumber.from(
                    (await this.aAdapter.mAdapter()).accTokenPerShare
                ).gt(BigNumber.from(this.accTokenPerShare))
            ).to.eq(true);

            this.accTokenPerShare = (
                await this.aAdapter.mAdapter()
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
                .add(tx1.gasUsed.mul("1000000007"))
                .sub(beforeAmt1);
            treasuryAmt1 = (
                await ethers.provider.getBalance(this.treasuryAddr)
            ).sub(treasuryAmt1);

            // check protocol fee
            expect(actualReward1.div(99)).to.eq(treasuryAmt1);

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
                .add(tx2.gasUsed.mul("1000000007"))
                .sub(beforeAmt2);
            treasuryAmt2 = (
                await ethers.provider.getBalance(this.treasuryAddr)
            ).sub(treasuryAmt2);

            // check protocol fee
            expect(actualReward2.div(99)).to.eq(treasuryAmt2);

            // Check mixed adapter reward results
            expect(
                BigNumber.from(actualReward2).gt(
                    BigNumber.from(actualReward1).mul(9)
                )
            ).to.eq(true);
        });
    });
});
