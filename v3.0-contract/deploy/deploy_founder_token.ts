import { ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";

import { verify } from "../utils";

async function deploy() {
    // pay token
    const BNB = "0x0000000000000000000000000000000000000000";
    const USDC = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
    const TUSD = "0x40af3827F39D0EAcBF4A168f8D4ee67c121D11c9";
    const USDT = "0x55d398326f99059fF775485246999027B3197955";
    const DAI = "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3";

    // pay token chainlink price feed
    const BNB_USD = "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE";
    const USDC_USD = "0x51597f405303C4377E36123cBc172b13269EA163";
    const TUSD_USD = "0xa3334A9762090E827413A7495AfeCE76F41dFc06";
    const USDT_USD = "0xB97Ad0E74fa7d920791E90258A6E2085088b4320";
    const DAI_USD = "0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA";

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
