const { expect } = require("chai");
const { ethers } = require("hardhat");

const { setupHedgepie, setupBscAdapterWithLib } = require("../shared/setup");

describe("Adapterlist test case", function () {
    before("Deploy contract", async function () {
        [this.governor, this.pathManager, this.adapterManager, this.treasury] = await ethers.getSigners();

        // Get base contracts
        [this.investor, this.authority, this.ybNft, this.adapterList, this.pathFinder, this.lib] = await setupHedgepie(
            this.governor,
            this.pathManager,
            this.adapterManager,
            this.treasury
        );

        const bsw = "0x965f527d9159dce6288a2219db51fc6eef120dd1";
        const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
        const busd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";

        const pksRouter = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
        const biswapRouter = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8";

        this.adapter = [0, 0, 0, 0, 0, 0, 0];
        this.cnt = 30;
        for (let ii = 0; ii < this.cnt; ii++) {
            // Deploy PancakeSwapFarmLPAdapterBsc contract
            const pksMasterChef = "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652"; // MasterChef v2 pks
            const pksLpToken = "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0"; // WBNB-CAKE LP
            const PancakeSwapFarmLPAdapterBsc = await setupBscAdapterWithLib("PancakeSwapFarmLPAdapterBsc", this.lib);
            this.adapter[0] = await PancakeSwapFarmLPAdapterBsc.deploy(
                2, // pid
                pksMasterChef,
                pksLpToken,
                cake,
                pksRouter,
                "PancakeSwap::Farm::CAKE-WBNB",
                this.authority.address
            );
            await this.adapter[0].deployed();

            // Deploy PancakeStakeAdapterBsc contract
            const pksStakeStrategy = "0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3";
            const pksStakeReward = "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd"; // SQUAD
            const PancakeStakeAdapterBsc = await setupBscAdapterWithLib("PancakeStakeAdapterBsc", this.lib);
            this.adapter[1] = await PancakeStakeAdapterBsc.deploy(
                pksStakeStrategy,
                cake,
                pksStakeReward,
                pksRouter,
                "PK::STAKE::SQUAD-ADAPTER",
                this.authority.address
            );
            await this.adapter[1].deployed();

            // Deploy BiswapFarmLPAdapterBsc contract
            const biswapStrategy = "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739"; // MasterChef Biswap
            const biswapLpToken = "0x2b30c317ceDFb554Ec525F85E79538D59970BEb0"; // USDT-BSW LP
            const BiswapFarmLPAdapterBsc = await setupBscAdapterWithLib("BiSwapFarmLPAdapterBsc", this.lib);
            this.adapter[2] = await BiswapFarmLPAdapterBsc.deploy(
                9, // pid
                biswapStrategy,
                biswapLpToken,
                bsw,
                biswapRouter,
                biswapRouter,
                "Biswap::Farm::USDT-BSW",
                this.authority.address
            );
            await this.adapter[2].deployed();

            // Deploy BiswapBSWPoolAdapterBsc contract
            const BiswapBSWPoolAdapterBsc = await setupBscAdapterWithLib("BiSwapFarmLPAdapterBsc", this.lib);
            this.adapter[3] = await BiswapBSWPoolAdapterBsc.deploy(
                0, // pid
                biswapStrategy,
                bsw,
                bsw,
                ethers.constants.AddressZero,
                biswapRouter,
                "Biswap::Pool::BSW",
                this.authority.address
            );
            await this.adapter[3].deployed();

            // Deploy AutoVaultAdapterBsc contract
            const autofarmStrategy = "0x0895196562C7868C5Be92459FaE7f877ED450452"; // MasterChef
            const autofarmVStrategy = "0xcFF7815e0e85a447b0C21C94D25434d1D0F718D1"; // vStrategy of vault
            const autofarmStaking = "0x0ed7e52944161450477ee417de9cd3a859b14fd0"; // WBNB-Cake LP
            const AutoFarmAdapter = await setupBscAdapterWithLib("AutoVaultAdapterBsc", this.lib);
            this.adapter[4] = await AutoFarmAdapter.deploy(
                619,
                autofarmStrategy,
                autofarmVStrategy,
                autofarmStaking,
                pksRouter,
                pksRouter,
                "AutoFarm::Vault::WBNB-CAKE",
                this.authority.address
            );
            await this.adapter[4].deployed();

            // Deploy BeltVaultAdapterBsc contract
            const beltStrategy = "0x9171Bf7c050aC8B4cf7835e51F7b4841DFB2cCD0"; // beltBUSD
            const BeltVaultAdapter = await setupBscAdapterWithLib("BeltVaultAdapterBsc", this.lib);
            this.adapter[5] = await BeltVaultAdapter.deploy(
                beltStrategy,
                busd,
                beltStrategy,
                pksRouter,
                "Belt::Vault::BUSD",
                this.authority.address
            );
            await this.adapter[5].deployed();

            // Deploy BeefyVaultAdapterBsc contract
            const beefyStrategy = "0x164fb78cAf2730eFD63380c2a645c32eBa1C52bc"; // Moo BiSwap USDT-BUSD
            const beefyStaking = "0xDA8ceb724A06819c0A5cDb4304ea0cB27F8304cF"; // Biswap USDT-BUSD LP
            const BeefyVaultAdapter = await setupBscAdapterWithLib("BeefyVaultAdapterBsc", this.lib);
            this.adapter[6] = await BeefyVaultAdapter.deploy(
                beefyStrategy,
                beefyStaking,
                biswapRouter,
                pksRouter,
                "Beefy::Vault::Biswap USDT-BUSD",
                this.authority.address
            );
            await this.adapter[6].deployed();

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
        }

        this.deactivateList = [];
        this.totalCnt = this.adapter.length * this.cnt;

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

    it("Check adapter list", async function () {
        const adapterlist = await this.adapterList.getAdapterList();
        expect(adapterlist.length).to.be.eq(this.totalCnt);
    });

    it("Deactivate some adapters", async function () {
        // deactivate 30 adapters
        await expect(this.adapterList.connect(this.governor).setAdapters([1], [false])).to.be.revertedWith(
            "UNAUTHORIZED"
        );

        let statuslist = [];
        for (let ii = 0; ii < 50; ii++) {
            const rndId = Math.floor(Math.random() * this.totalCnt);

            if (this.deactivateList.indexOf(rndId) < 0) {
                this.deactivateList.push(rndId);
                statuslist.push(false);
            }
        }

        await this.adapterList.connect(this.adapterManager).setAdapters(this.deactivateList, statuslist);
    });

    it("Check active adpater list after deactivated", async function () {
        const adapterlist = await this.adapterList.getAdapterList();
        expect(adapterlist.length).to.be.eq(this.totalCnt);

        const startInd = this.totalCnt - this.deactivateList.length;
        for (let ii = startInd; ii < this.totalCnt; ii++) {
            expect(adapterlist[ii].addr).to.be.eq(ethers.constants.AddressZero);
        }
    });

    it("Check deactivated adpater list after deactivated", async function () {
        const deactiveList = await this.adapterList.getDeactiveList();
        expect(deactiveList.length).to.be.eq(this.totalCnt);

        for (let ii = this.deactivateList.length; ii < this.totalCnt; ii++) {
            expect(deactiveList[ii].addr).to.be.eq(ethers.constants.AddressZero);
        }
    });
});
