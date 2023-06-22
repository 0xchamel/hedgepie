const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setupHedgepie, setupBscAdapterWithLib } = require("../shared/setup");

describe.only("Update adapterlabel test case", function () {
    before("Deploy contract", async function () {
        [this.governor, this.pathManager, this.adapterManager, this.treasury] = await ethers.getSigners();

        // Get base contracts
        [this.investor, this.authority, this.ybNft, this.adapterList, this.pathFinder, this.lib] = await setupHedgepie(
            this.governor,
            this.pathManager,
            this.adapterManager,
            this.treasury
        );

        const poolID = 2;
        const strategy = "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652"; // MasterChef v2 pks
        const lpToken = "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0"; // WBNB-CAKE LP
        const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
        const pksRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

        const PancakeSwapFarmLPAdapterBsc = await setupBscAdapterWithLib("PancakeSwapFarmLPAdapterBsc", this.lib);
        this.adapter = await PancakeSwapFarmLPAdapterBsc.deploy(
            poolID, // pid
            strategy,
            lpToken,
            cake,
            pksRouter,
            "PKS::Farm::CAKE-WBNB",
            this.authority.address
        );
        await this.adapter.deployed();

        this.newlabel = "Pancakeswap::Farm::CAKE-WBNB";
    });

    it("Check current label", async function () {
        const adapterlabel = await this.adapter.label();
        expect(adapterlabel).to.be.eq("PKS::Farm::CAKE-WBNB");
    });

    it("Only adaptermanager can change the label", async function () {
        await expect(this.adapter.connect(this.governor).updateLabel(this.newlabel)).to.be.revertedWith("UNAUTHORIZED");

        await expect(this.adapter.connect(this.pathManager).updateLabel(this.newlabel)).to.be.revertedWith(
            "UNAUTHORIZED"
        );

        await expect(this.adapter.connect(this.treasury).updateLabel(this.newlabel)).to.be.revertedWith("UNAUTHORIZED");
    });

    it("Check updated label", async function () {
        await this.adapter.connect(this.adapterManager).updateLabel(this.newlabel);

        const adapterlabel = await this.adapter.label();
        expect(adapterlabel).to.be.eq(this.newlabel);
    });
});
