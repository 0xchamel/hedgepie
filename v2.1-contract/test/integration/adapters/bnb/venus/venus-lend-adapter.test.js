const { assert, expect } = require("chai");
const { ethers } = require("hardhat");

const { setPath } = require("../../../../shared/utilities");
const {
    adapterFixtureBsc,
    investorFixtureBsc,
} = require("../../../../shared/fixtures");

const BigNumber = ethers.BigNumber;

describe("VenusLendAdapterBsc Integration Test", function () {
    before("Deploy contract", async function () {
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const busd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
        const vbusd = "0x95c78222B3D6e262426483D42CfA53685A67Ab9D";
        const venusLens = "0x7fd7E938d575Fe8ccF72ED65a82142D154C170Af";

        const [owner, alice, bob, treasury] = await ethers.getSigners();

        this.performanceFee = 500;
        this.alice = alice;
        this.owner = owner;
        this.bob = bob;
        this.strategy = vbusd;
        this.busd = busd;
        this.treasuryAddr = treasury.address;

        // Deploy VenusLendAdapterBsc contract
        const VenusLendAdapterBsc = await adapterFixtureBsc(
            "VenusLendAdapterBsc"
        );

        this.adapter = await VenusLendAdapterBsc.deploy(
            this.strategy,
            venusLens,
            busd,
            vbusd,
            swapRouter,
            wbnb,
            "Venus::BUSD::Lend"
        );
        await this.adapter.deployed();

        [this.adapterInfo, this.investor, this.ybNft] =
            await investorFixtureBsc(
                this.adapter,
                treasury.address,
                busd,
                this.performanceFee
            );

        await setPath(this.adapter, wbnb, busd);

        console.log("YBNFT: ", this.ybNft.address);
        console.log("Investor: ", this.investor.address);
        console.log("VenusAdapter: ", this.adapter.address);
        console.log("Strategy: ", this.strategy);
        console.log("Owner: ", this.owner.address);

        this.vBUSD = await ethers.getContractAt("VBep20Interface", vbusd);
        this.BUSD = await ethers.getContractAt("VBep20Interface", busd);
        this.WBNB = await ethers.getContractAt("VBep20Interface", wbnb);
    });

    describe("should set correct state variable", function () {
        it("(1) Check strategy address", async function () {
            expect(await this.adapter.strategy()).to.eq(this.strategy);
        });

        it("(2) Check owner wallet", async function () {
            expect(await this.adapter.owner()).to.eq(this.owner.address);
        });

        it("(3) Check owner wallet", async function () {
            expect(await this.adapter.owner()).to.eq(this.owner.address);
        });

        it("(4) Check AdapterInfo of YBNFT", async function () {
            const response = await this.ybNft.getAdapterInfo(1);
            expect(response[0].allocation).to.eq(10000) &&
                expect(response[0].token).to.eq(this.busd) &&
                expect(response[0].addr).to.eq(this.adapter.address);
        });
    });

    describe("deposit() function test", function () {
        it("(1)should be reverted when nft tokenId is invalid", async function () {
            // deposit to nftID: 3
            const depositAmount = ethers.utils.parseEther("1");
            await expect(
                this.investor.depositBNB(3, depositAmount.toString(), {
                    gasPrice: 21e9,
                    value: depositAmount.toString(),
                })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2)should be reverted when amount is 0", async function () {
            // deposit to nftID: 1
            const depositAmount = ethers.utils.parseEther("0");
            await expect(
                this.investor.depositBNB(1, depositAmount.toString(), {
                    gasPrice: 21e9,
                    value: depositAmount.toString(),
                })
            ).to.be.revertedWith("Error: Insufficient BNB");
        });

        it("(3)should success 1 time and receive the vToken successfully after deposit function", async function () {
            const depositAmount = ethers.utils.parseEther("1");

            await this.investor.depositBNB(1, depositAmount, {
                gasPrice: 21e9,
                value: depositAmount.toString(),
            });

            expect(
                BigNumber.from(
                    await this.vBUSD.balanceOf(this.adapter.address)
                ).gt(0)
            ).to.eq(true);
        });

        it("(4)should success multiple times", async function () {
            // deposit to nftID: 1
            let vBeforeBal = BigNumber.from(
                await this.vBUSD.balanceOf(this.adapter.address)
            );

            const depositAmount = ethers.utils.parseEther("1");
            await this.investor.depositBNB(1, depositAmount.toString(), {
                gasPrice: 21e9,
                value: depositAmount.toString(),
            });

            await this.investor.depositBNB(2, depositAmount.toString(), {
                gasPrice: 21e9,
                value: depositAmount.toString(),
            });

            let vAfterBal = BigNumber.from(
                await this.vBUSD.balanceOf(this.adapter.address)
            );

            expect(vAfterBal.gt(vBeforeBal)).to.eq(true);
        });
    });

    describe("check withdrawal amount", function() {
        it("(1) check withdrawal amount", async function() {
            const userPending = await this.investor.pendingReward(
                1,
                this.owner.address
            )
            expect(userPending.amountOut).gt(0)
            expect(userPending.withdrawable).to.be.eq(0)
        })
    });

    describe("withdraw() function test", function () {
        it("(1)should be reverted when nft tokenId is invalid", async function () {
            // withdraw to nftID: 3
            await expect(
                this.investor.withdrawBNB(3, {
                    gasPrice: 21e9,
                })
            ).to.be.revertedWith("Error: nft tokenId is invalid");
        });

        it("(2)should be reverted when amount is 0", async function () {
            // deposit to nftID: 1
            const depositAmount = ethers.utils.parseEther("0");
            await expect(
                this.investor
                    .connect(this.bob)
                    .depositBNB(1, depositAmount.toString(), {
                        gasPrice: 21e9,
                    })
            ).to.be.revertedWith("Error: Insufficient BNB");
        });

        it("(3)should receive the WBNB successfully after withdraw function", async function () {
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 300]);
            await ethers.provider.send("evm_mine", []);
            
            // withdraw from nftId: 1
            let userInfo = (
                await this.adapter.userAdapterInfos(this.owner.address, 1)
            ).invested;
            let bnbBalBefore = await ethers.provider.getBalance(
                this.owner.address
            );
            let userPending = await this.investor.pendingReward(
                1,
                this.owner.address
            )
            let beforeTreasuryBnb = await ethers.provider.getBalance(
                this.treasuryAddr
            );

            const withdrawTx = await this.investor.connect(this.owner).withdrawBNB(1);
            const withdrawResp = await withdrawTx.wait()

            let bnbBalAfter = await ethers.provider.getBalance(
                this.owner.address
            );
            expect(
                BigNumber.from(bnbBalAfter).gt(BigNumber.from(bnbBalBefore))
            ).to.eq(true);

            const gasAmt = withdrawResp.gasUsed.mul("1000000007")
            const actualPending = bnbBalAfter.add(gasAmt).sub(bnbBalBefore)
            let afterTreasuryBnb = await ethers.provider.getBalance(
                this.treasuryAddr
            );

            if (actualPending.gt(userInfo)) { 
                actualPending = actualPending.sub(BigNumber.from(userInfo));
                const protocolFee = afterTreasuryBnb.sub(beforeTreasuryBnb);
                expect(protocolFee).to.gt(0);

                expect(actualPending).to.be.within(
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .sub(gasAmt),
                    protocolFee
                        .mul(1e4 - this.performanceFee)
                        .div(this.performanceFee)
                        .add(gasAmt)
                )
                
                const estimatePending = BigNumber.from(userPending.amountOut).mul(
                    1e4 - this.performanceFee
                ).div(1e4)
                expect(actualPending).gte(
                    estimatePending.mul(98).div(1e2)
                )
            }

            // withdraw from nftId: 2
            bnbBalBefore = await ethers.provider.getBalance(this.owner.address);
            await this.investor.withdrawBNB(2, {
                gasPrice: 21e9,
            });

            bnbBalAfter = await ethers.provider.getBalance(this.owner.address);
            expect(
                BigNumber.from(bnbBalAfter).gte(BigNumber.from(bnbBalBefore))
            ).to.eq(true);
        });
    });
});
