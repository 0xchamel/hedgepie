import { ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";

import { verify } from "../utils";

async function deploy() {
    // pay token
    const BNB = "0x0000000000000000000000000000000000000000";
    const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const TUSD = "0x0000000000085d4780B73119b644AE5ecd22b376";
    const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    // pay token chainlink price feed
    const BNB_USD = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
    const USDC_USD = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";
    const TUSD_USD = "0xec746eCF986E2927Abd291a2A1716c940100f8Ba";
    const USDT_USD = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
    const DAI_USD = "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9";

    /* treausur address
     ** dev: 0x2498B5162206E86a9DB305709B1f8DAC71789815
     ** prod: 0x3Eda5A38dda554879D1e1e984e27Ee3d6d816d99
     */
    const treauryAddr = "0x3Eda5A38dda554879D1e1e984e27Ee3d6d816d99";

    // deploy HedgepieFounderToken contract
    const HPFT = await ethers.getContractFactory("HedgepieFounderToken");
    const hpft = await HPFT.deploy(treauryAddr);
    await hpft.deployed();
    console.log("HedgepieFounderToken contract deployed: ", hpft.address);
    console.log("Treasury: ", treauryAddr);

    // verify HedgepieFounderToken contract
    await verify({
        contractName: "HedgepieFounderToken",
        address: hpft.address,
        constructorArguments: [treauryAddr],
        contractPath: "contracts/base/HedgepieFounderToken.sol:HedgepieFounderToken",
    });

    // set pay token list
    await await hpft.addPayToken(BNB, BNB_USD);
    await await hpft.addPayToken(USDC, USDC_USD);
    await await hpft.addPayToken(TUSD, TUSD_USD);
    await await hpft.addPayToken(USDT, USDT_USD);
    await await hpft.addPayToken(DAI, DAI_USD);
}

async function main() {
    await deploy();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
