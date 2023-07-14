const { expect } = require("chai");
const { ethers } = require("hardhat");
const { forkBNBNetwork, unlockAccount } = require("../shared/utilities");
const { utils } = require("ethers");
const ERC20Abi = require("../shared/abi/ERC20.json");

const BigNumber = ethers.BigNumber;

describe("HedgePie Founder token Test", function () {
    before("Deploy contract", async function () {
        await forkBNBNetwork();

        [this.owner, this.treasury, this.user1, this.user2] = await ethers.getSigners();

        // pay token
        const BNB = "0x0000000000000000000000000000000000000000";
        const USDC = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
        const TUSD = "0x40af3827F39D0EAcBF4A168f8D4ee67c121D11c9";
        const USDT = "0x55d398326f99059fF775485246999027B3197955";
        const DAI = "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3";
        const BUSD = "0xe9e7cea3dedca5984780bafc599bd69add087d56";

        // pay token chainlink price feed
        const BNB_USD = "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE";
        const USDC_USD = "0x51597f405303C4377E36123cBc172b13269EA163";
        const TUSD_USD = "0xa3334A9762090E827413A7495AfeCE76F41dFc06";
        const USDT_USD = "0xB97Ad0E74fa7d920791E90258A6E2085088b4320";
        const DAI_USD = "0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA";

        const MAX_SUPPLY = 5000000; // 5 million
        const SALE_PRICE = 0.5; // $0.5

        // set token
        this.bnb = BNB;
        this.usdc = USDC;
        this.tusd = TUSD;
        this.usdt = USDT;
        this.dai = DAI;
        this.busd = BUSD;

        this.bnbUsd = BNB_USD;
        this.usdcUsd = USDC_USD;
        this.tusdUsd = TUSD_USD;
        this.usdtUsd = USDT_USD;
        this.daiUsd = DAI_USD;

        this.whaleAddr = "0x8894E0a0c962CB723c1976a4421c95949bE2D4E3";
        this.whale = await unlockAccount(this.whaleAddr);
        this.treasuryAddress = this.treasury.address;
        this.maxSupply = utils.parseUnits(String(MAX_SUPPLY));
        this.salePrice = utils.parseUnits(String(SALE_PRICE), 8);

        // deploy Hedgepie Founder token contract
        const HPFT = await ethers.getContractFactory("HedgepieFounderToken");
        this.hpft = await HPFT.deploy(this.treasuryAddress);
        await this.hpft.deployed();

        // set pay token list
        await this.hpft.connect(this.owner).addPayToken(BNB, BNB_USD);
        await this.hpft.connect(this.owner).addPayToken(USDC, USDC_USD);
        await this.hpft.connect(this.owner).addPayToken(TUSD, TUSD_USD);
        await this.hpft.connect(this.owner).addPayToken(USDT, USDT_USD);
        await this.hpft.connect(this.owner).addPayToken(DAI, DAI_USD);

        console.log("Hedgepie Founder token: ", this.hpft.address);
        console.log("Treasury address: ", this.treasuryAddress);
        console.log("Max Supply: ", this.maxSupply);
        console.log("Sale Price: ", this.salePrice);

        console.log("BNB pay token listed: ", this.bnb);
        console.log("USDC pay token listed: ", this.usdc);
        console.log("TUSD pay token listed: ", this.tusd);
        console.log("USDT pay token listed: ", this.usdt);
        console.log("DAI pay token listed: ", this.dai);
    });

    describe("Check init variables", function () {
        it("(1) check treasury address", async function () {
            expect(await this.hpft.treasury()).to.eq(this.treasuryAddress);
        });
        it("(2) check max supply", async function () {
            expect(await this.hpft.maxSupply()).to.eq(this.maxSupply);
        });
        it("(3) check sale price", async function () {
            expect(await this.hpft.salePrice()).to.eq(this.salePrice);
        });
        it("(4) check pay token list", async function () {
            expect((await this.hpft.payTokenList(this.bnb)).chainlinkPriceFeed).to.eq(this.bnbUsd);
            expect((await this.hpft.payTokenList(this.usdc)).chainlinkPriceFeed).to.eq(this.usdcUsd);
            expect((await this.hpft.payTokenList(this.tusd)).chainlinkPriceFeed).to.eq(this.tusdUsd);
            expect((await this.hpft.payTokenList(this.usdt)).chainlinkPriceFeed).to.eq(this.usdtUsd);
            expect((await this.hpft.payTokenList(this.dai)).chainlinkPriceFeed).to.eq(this.daiUsd);
        });
        it("(5) check availableCanPurchase amount", async function () {
            expect(await this.hpft.availableCanPurchase()).to.eq(this.maxSupply);
        });
    });

    describe("Check purchase function", function () {
        it("(1) should be reverted when purchase amount is bigger than available", async function () {
            const avaialbleAmount = await this.hpft.availableCanPurchase();
            const purchaseAmount = avaialbleAmount.add(BigNumber.from(1));
            const requiredPayTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.bnb);

            console.log("Avvailable amount: ", avaialbleAmount);
            console.log("Purchase amount: ", purchaseAmount);
            console.log("Pay token: ", this.bnb);
            console.log("Pay token amount: ", requiredPayTokenAmount);

            await expect(
                this.hpft.connect(this.user1).purchase(purchaseAmount, this.bnb, {
                    value: requiredPayTokenAmount,
                })
            ).to.be.revertedWith("Error: insufficient sale token");
        });

        it("(2) should be reverted when pay token is not listed", async function () {
            const avaialbleAmount = await this.hpft.availableCanPurchase();
            const purchaseAmount = avaialbleAmount;
            const requiredPayTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.busd);

            console.log("Avvailable amount: ", avaialbleAmount);
            console.log("Purchase amount: ", purchaseAmount);
            console.log("Pay token: ", this.busd);
            console.log("Pay token amount: ", requiredPayTokenAmount);

            await expect(this.hpft.connect(this.user1).purchase(purchaseAmount, this.busd)).to.be.revertedWith(
                "Error: not listed token"
            );
        });

        it("(3) should be reverted when pay token amount is insufficient", async function () {
            const avaialbleAmount = await this.hpft.availableCanPurchase();
            const purchaseAmount = avaialbleAmount;
            const requiredPayTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.bnb);
            const payTokenAmount = requiredPayTokenAmount.sub(BigNumber.from(1));

            console.log("Avvailable amount: ", avaialbleAmount);
            console.log("Purchase amount: ", purchaseAmount);
            console.log("Pay token: ", this.busd);
            console.log("Pay token amount: ", payTokenAmount);
            console.log("Required Pay token amount: ", requiredPayTokenAmount);

            await expect(
                this.hpft.connect(this.user1).purchase(purchaseAmount, this.bnb, {
                    value: payTokenAmount,
                })
            ).to.be.revertedWith("Error: insufficient BNB");
        });

        it("(4) should be able to purchase with BNB", async function () {
            const avaialbleAmount = await this.hpft.availableCanPurchase();
            const purchaseAmountRaw = 1000;
            const purchaseAmount = utils.parseUnits(String(purchaseAmountRaw));
            const requiredPayTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.bnb);
            const payTokenAmount = requiredPayTokenAmount;

            console.log("Avvailable amount: ", avaialbleAmount);
            console.log("Purchase amount: ", purchaseAmountRaw);
            console.log("Pay token: ", this.busd);
            console.log("Pay token amount: ", payTokenAmount);
            console.log("Required Pay token amount: ", requiredPayTokenAmount);

            const balanceBefore = await this.hpft.balanceOf(this.user1.address);

            await this.hpft.connect(this.user1).purchase(purchaseAmount, this.bnb, {
                value: payTokenAmount,
            });

            await this.hpft.connect(this.user1).purchase(purchaseAmount, this.bnb, {
                value: payTokenAmount,
            });

            const balanceAfter = await this.hpft.balanceOf(this.user1.address);
            expect(balanceBefore.add(purchaseAmount.mul(2))).to.be.eq(balanceAfter);

            console.log("\n=== Purchase success with BNB ===");
            console.log("HPFT token balance (before): ", balanceBefore);
            console.log("HPFT token balance (after): ", balanceAfter);
        });

        it("(5) should be able to purchase with USDC", async function () {
            const purchaseAmountRaw = 1000;
            const purchaseAmount = utils.parseUnits(String(purchaseAmountRaw));
            const payTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.usdc);

            const payToken = await ethers.getContractAt(ERC20Abi, this.usdc);
            await payToken.connect(this.whale).transfer(this.user1.address, payTokenAmount);
            await payToken.connect(this.user1).approve(this.hpft.address, payTokenAmount);

            const balanceBefore = await this.hpft.balanceOf(this.user1.address);
            const treasuryBalBefore = await payToken.balanceOf(this.treasuryAddress);
            await this.hpft.connect(this.user1).purchase(purchaseAmount, this.usdc);
            const balanceAfter = await this.hpft.balanceOf(this.user1.address);
            const treasuryBalAfter = await payToken.balanceOf(this.treasuryAddress);

            console.log("\n=== Purchase success with USDC ===");
            console.log("HPFT token balance (before): ", balanceBefore);
            console.log("HPFT token balance (after): ", balanceAfter);
            console.log("Treasury USDC token balance (before): ", treasuryBalBefore);
            console.log("Treasury USDC token balance (after): ", treasuryBalAfter);

            expect(balanceBefore.add(purchaseAmount)).to.be.eq(balanceAfter);
        });

        it("(6) should be able to purchase with USDT", async function () {
            const purchaseAmountRaw = 1000;
            const purchaseAmount = utils.parseUnits(String(purchaseAmountRaw));
            const payTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.usdt);

            const payToken = await ethers.getContractAt(ERC20Abi, this.usdt);
            await payToken.connect(this.whale).transfer(this.user1.address, payTokenAmount);
            await payToken.connect(this.user1).approve(this.hpft.address, payTokenAmount);

            const balanceBefore = await this.hpft.balanceOf(this.user1.address);
            await this.hpft.connect(this.user1).purchase(purchaseAmount, this.usdt);
            const balanceAfter = await this.hpft.balanceOf(this.user1.address);

            console.log("\n=== Purchase success with USDT ===");
            console.log("HPFT token balance (before): ", balanceBefore);
            console.log("HPFT token balance (after): ", balanceAfter);

            expect(balanceBefore.add(purchaseAmount)).to.be.eq(balanceAfter);
        });

        it("(7) should be able to purchase with DAI", async function () {
            const purchaseAmountRaw = 1000;
            const purchaseAmount = utils.parseUnits(String(purchaseAmountRaw));
            const payTokenAmount = await this.hpft.getRequiredPayTokenAmount(purchaseAmount, this.dai);

            const payToken = await ethers.getContractAt(ERC20Abi, this.dai);
            await payToken.connect(this.whale).transfer(this.user1.address, payTokenAmount);
            await payToken.connect(this.user1).approve(this.hpft.address, payTokenAmount);

            const balanceBefore = await this.hpft.balanceOf(this.user1.address);
            await this.hpft.connect(this.user1).purchase(purchaseAmount, this.dai);
            const balanceAfter = await this.hpft.balanceOf(this.user1.address);

            console.log("\n=== Purchase success with DAI ===");
            console.log("HPFT token balance (before): ", balanceBefore);
            console.log("HPFT token balance (after): ", balanceAfter);

            expect(balanceBefore.add(purchaseAmount)).to.be.eq(balanceAfter);
        });
    });
});
