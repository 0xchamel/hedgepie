const { expect } = require("chai");
const { ethers } = require("hardhat");
const { forkBNBNetwork, setPath } = require("../shared/utilities");
const { mintNFT, setupHedgepie, setupBscAdapterWithLib } = require("../shared/setup");

const BigNumber = ethers.BigNumber;

describe("YBNFT Unit Test", function () {
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
        const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
        const stakingToken = "0xDA8ceb724A06819c0A5cDb4304ea0cB27F8304cF"; // Biswap USDT-BUSD LP
        const strategy = "0x164fb78cAf2730eFD63380c2a645c32eBa1C52bc"; // Moo BiSwap USDT-BUSD
        const router = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8"; // Biswap router
        const swapRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // pks rounter address
        const name = "Beefy::Vault::Biswap USDT-BUSD";
        const USDT = "0x55d398326f99059fF775485246999027B3197955";
        const BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

        this.performanceFee = 500;
        this.accRewardShare = BigNumber.from(0);

        // Deploy BeefyVaultAdapterBsc contract
        const BeefyVaultAdapter = await setupBscAdapterWithLib("BeefyVaultAdapterBsc", this.lib);
        this.adapter = [0, 0, 0];
        this.adapter[0] = await BeefyVaultAdapter.deploy(
            strategy,
            stakingToken,
            router,
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

        this.adapter[2] = await PancakeStakeAdapterBsc.deploy(
            this.strategy,
            this.stakingToken,
            this.rewardToken,
            this.swapRouter,
            "PK::STAKE::SQUAD-ADAPTER",
            this.authority.address
        );
        await this.adapter[2].deployed();

        // register path to pathFinder contract
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake]);
        await setPath(this.pathFinder, this.pathManager, this.swapRouter, [wbnb, cake, this.rewardToken]);
        await setPath(this.pathFinder, this.pathManager, router, [wbnb, USDT]);
        await setPath(this.pathFinder, this.pathManager, router, [wbnb, BUSD]);
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, USDT]);
        await setPath(this.pathFinder, this.pathManager, swapRouter, [wbnb, BUSD]);

        // add adapters to adapterList
        await this.adapterList
            .connect(this.adapterManager)
            .addAdapters([this.adapter[0].address, this.adapter[1].address]);

        // mint ybnft
        await mintNFT(this.ybNft, [this.adapter[0].address, this.adapter[1].address], this.performanceFee);

        console.log("Lib: ", this.lib.address);
        console.log("YBNFT: ", this.ybNft.address);
        console.log("Investor: ", this.investor.address);
        console.log("Authority: ", this.authority.address);
        console.log("AdapterList: ", this.adapterList.address);
        console.log("PathFinder: ", this.pathFinder.address);
    });

    describe("Check init variables", function () {
        it("(1) check exists", async function () {
            expect(await this.ybNft.exists(1)).to.eq(true) &&
                expect(await this.ybNft.exists(2)).to.eq(true) &&
                expect(await this.ybNft.exists(3)).to.eq(false);
        });

        it("(2) check performance fee", async function () {
            expect(await this.ybNft.performanceFee(1)).to.eq(this.performanceFee) &&
                expect(await this.ybNft.performanceFee(2)).to.eq(this.performanceFee);
        });

        it("(3) check adaper param information", async function () {
            const param10 = await this.ybNft.adapterParams(1, 0);
            const param11 = await this.ybNft.adapterParams(1, 1);
            const param20 = await this.ybNft.adapterParams(2, 0);
            const param21 = await this.ybNft.adapterParams(2, 1);

            expect(param10.addr).to.eq(this.adapter[0].address) &&
                expect(param11.addr).to.eq(this.adapter[1].address) &&
                expect(param10.allocation).to.eq(5000) &&
                expect(param11.allocation).to.eq(5000) &&
                expect(param20.addr).to.eq(this.adapter[0].address) &&
                expect(param21.addr).to.eq(this.adapter[1].address) &&
                expect(param20.allocation).to.eq(5000) &&
                expect(param21.allocation).to.eq(5000);
        });

        it("(4) check adaper param information", async function () {
            const date1 = await this.ybNft.adapterDate(1);
            const date2 = await this.ybNft.adapterDate(2);

            expect(date1.created).to.eq(date1.modified) &&
                expect(date1.created).to.gt(0) &&
                expect(date2.created).to.eq(date2.modified) &&
                expect(date2.created).to.gt(0);
        });

        it("(5) check current token id", async function () {
            expect(await this.ybNft.getCurrentTokenId()).to.eq(2);
        });
    });

    describe("Check mint validations", function () {
        it("(1) test performance fee validation", async function () {
            await expect(
                this.ybNft.mint(
                    [
                        [5000, this.adapter[0].address],
                        [5000, this.adapter[1].address],
                    ],
                    1001,
                    "test tokenURI1"
                )
            ).to.be.revertedWith("Fee should be less than 10%");
        });

        it("(2) test adapterParam length validation", async function () {
            await expect(this.ybNft.mint([], this.performanceFee, "test tokenURI1")).to.be.revertedWith(
                "Mismatched adapters"
            );
        });

        it("(3) test allocation validation", async function () {
            await expect(
                this.ybNft.mint(
                    [
                        [5000, this.adapter[0].address],
                        [6000, this.adapter[1].address],
                    ],
                    this.performanceFee,
                    "test tokenURI1"
                )
            ).to.be.revertedWith("Incorrect adapter allocation");
        });
    });

    describe("Check update performance fee", function () {
        it("(1) revert when performance fee is bigger than 10%", async function () {
            await expect(this.ybNft.updatePerformanceFee(1, 10001)).to.be.revertedWith("Fee should be under 10%");
        });

        it("(2) revert when performance fee isn't being updated from owner", async function () {
            await expect(this.ybNft.connect(this.bob).updatePerformanceFee(1, 900)).to.be.revertedWith(
                "Invalid NFT Owner"
            );
        });

        it("(3) test updating performance fee", async function () {
            await this.ybNft.updatePerformanceFee(1, 100);

            expect(await this.ybNft.performanceFee(1)).to.eq(100);
        });
    });

    describe("Check update token URI", function () {
        it("(1) revert when performance fee isn't being updated from owner", async function () {
            await expect(this.ybNft.connect(this.bob).updateTokenURI(1, "URI")).to.be.revertedWith("Invalid NFT Owner");
        });

        it("(2) test updating token URI", async function () {
            await this.ybNft.updateTokenURI(1, "URI");

            expect(await this.ybNft.tokenURI(1)).to.eq("URI");
        });
    });

    describe("Check update allocation", function () {
        it("(1) revert when allocation isn't being updated from owner", async function () {
            await expect(
                this.ybNft.connect(this.bob).updateAllocations(1, [
                    [1000, this.adapter[0].address],
                    [9000, this.adapter[1].address],
                ])
            ).to.be.revertedWith("Invalid NFT Owner");
        });

        it("(2) revert when adapter length is mismatch", async function () {
            await expect(this.ybNft.updateAllocations(1, [[9000, this.adapter[1].address]])).to.be.revertedWith(
                "Invalid allocation length"
            );
        });

        it("(3) revert when allocaion is not fully set", async function () {
            await expect(
                this.ybNft.updateAllocations(1, [
                    [1000, this.adapter[0].address],
                    [9001, this.adapter[1].address],
                ])
            ).to.be.revertedWith("Incorrect adapter allocation");
        });

        it("(4) revert when adding adapter not listed", async function () {
            await expect(
                this.ybNft.updateAllocations(1, [
                    [1000, this.adapter[0].address],
                    [2000, this.adapter[1].address],
                    [7000, this.adapter[2].address],
                ])
            ).to.be.revertedWith("Adapter address mismatch");
        });

        it("(5) test updating allocation", async function () {
            // add adapters to adapterList
            await this.adapterList.connect(this.adapterManager).addAdapters([this.adapter[2].address]);

            await this.ybNft.updateAllocations(1, [
                [1000, this.adapter[0].address],
                [2000, this.adapter[1].address],
                [7000, this.adapter[2].address],
            ]);

            const param10 = await this.ybNft.adapterParams(1, 0);
            const param11 = await this.ybNft.adapterParams(1, 1);
            const param21 = await this.ybNft.adapterParams(1, 2);

            expect(param10.allocation).to.eq(1000) &&
                expect(param11.allocation).to.eq(2000) &&
                expect(param21.allocation).to.eq(7000);
        });
    });

    describe("Check onlyInvestor function validations", function () {
        it("(1) revert updateProfitInfo call not from investor", async function () {
            await expect(this.ybNft.connect(this.bob).updateProfitInfo(1, 1000)).to.be.revertedWith("UNAUTHORIZED");
        });

        it("(2) revert updateInfo call not from investor", async function () {
            await expect(this.ybNft.connect(this.bob).updateInfo([1, 1, this.bob.address, 0])).to.be.revertedWith(
                "UNAUTHORIZED"
            );
        });
    });
});
