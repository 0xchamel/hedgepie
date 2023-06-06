import contracts from "../config/contracts_stg.json";

export const lib = { address: (contracts as any).lib };

export const authority = (contracts as any)?.authority;

export const adapters = {
    radiant: [
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0x55d398326f99059fF775485246999027B3197955",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x4Ff2DD7c6435789E0BB56B0553142Ad00878a004",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::USDT",
            authority,
        ],
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x34d4F4459c1b529BEbE1c426F1e584151BE2C1e5",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::BTCB",
            authority,
        ],
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x89d763e8532D256a3e3e60c1C218Ac71E71cF664",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::BUSD",
            authority,
        ],
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x455a281D508B4e34d55b31AC2e4579BD9b77cA8E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::ETH",
            authority,
        ],
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x58b0BB56CFDfc5192989461dD43568bcfB2797Db",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::BNB",
            authority,
        ],
        [
            "0xd50Cf00b6e600Dd036Ba8eF475677d816d6c4281",
            "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d",
            "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF",
            "0x3bDCEf9e656fD9D03eA98605946b4fbF362C342b",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x8fe962Dd1f322780f2Cb0264eA1eDc8a1504C367",
            "Radiant::Market::USDC",
            authority,
        ],
    ],
    pinkSwap: [
        [
            0,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0x61c960D0337f1EfE46BC7B1110bA8C4e60DD2017",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::PINKS-BNB",
            authority,
        ],
        [
            1,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0x2E4BaE64Cc33eC8A7608930E8Bd32f592E8a9968",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::BNB-BUSD",
            authority,
        ],
        [
            2,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0xB9eFbD2Bb41f7A2136BF2B21e8B26641651adef9",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::PINKE-BNB",
            authority,
        ],
        [
            3,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0xefd49d669d73Acf4dF4dF7C677F689Fc6ca6ecaB",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::USDT-BUSD",
            authority,
        ],
        [
            4,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0x5aB38077E9C5f9980bbabf68679B7E34137a51Af",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::ETH-BNB",
            authority,
        ],
        [
            5,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0xC4dBFe8860bd39F0F8281B7DE8eE53730c9a44e1",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::BTCB-BNB",
            authority,
        ],
        [
            6,
            "0xe981676633dcf0256aa512f4923a7e8da180c595",
            "0xb390F799ba5f75e0BB15014A9a34a0dEC6760E1E",
            "0x702b3f41772e321aacCdea91e1FCEF682D21125D",
            "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac",
            "PinkSwap::Farm::USDT-BNB",
            authority,
        ],
    ],
};

const pks = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const biswap = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8";
const mdex = "0x8fe32329C4dbE8d29B9c8874Ef0F52CcD8c7D3F0";
const pinkswap = "0x319ef69a98c8e8aab36aea561daba0bf3d0fa3ac";

const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const usdt = "0x55d398326f99059fF775485246999027B3197955";
const usdc = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
const busd = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const eth = "0x2170Ed0880ac9A755fd29B2688956BD959F933F8";
const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const ada = "0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47";
const dot = "0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402";
const btc = "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c";
const bsw = "0x965f527d9159dce6288a2219db51fc6eef120dd1";
const fil = "0x0d8ce2a99bb6e3b7db580ed848240e4a0f9ae153";
const trx = "0x85EAC5Ac2F758618dFa09bDbe0cf174e7d574D5B";
const arena = "0xCfFD4D3B517b77BE32C76DA768634dE6C738889B";
const champ = "0x7e9AB560d37E62883E882474b096643caB234B65";
const squad = "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd";
const xvs = "0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63";
const rdnt = "0xf7DE7E8A6bd59ED41a4b5fe50278b3B7f31384dF";
const ltc = "0x4338665CBB7B2485A8855A139b75D5e34AB0DB94";
const aave = "0xfb6115445Bff7b52FeB98650C87f44907E58f802";
const sxp = "0x47BEAd2563dCBf3bF2c9407fEa4dC236fAbA485A";
const xrp = "0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE";
const matic = "0xCC42724C6683B7E57334c4E856f4c9965ED682bD";
const dai = "0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3";
const alpaca = "0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F";
const tusd = "0x14016E85a25aeb13065688cAFB43044C2ef86784";
const ceek = "0xe0F94Ac5462997D2BC57287Ac3a3aE4C31345D66";
const mbox = "0x3203c9E46cA618C8C1cE5dC67e7e9D75f5da2377";
const sfp = "0xD41FDb03Ba84762dD66a0af1a6C8540FF1ba5dfb";
const doge = "0xbA2aE424d960c26247Dd6c32edC70B295c744C43";
const gmt = "0x3019BF2a2eF8040C242C9a4c5c4BD4C81678b2A1";
const id = "0x2dfF88A56767223A5529eA5960Da7A3F5f766406";
const wom = "0xAD6742A35fB341A9Cc6ad674738Dd8da98b94Fb1";
const high = "0x5f4Bde007Dc06b867f86EBFE4802e34A1fFEEd63";
const wmx = "0xa75d9ca2a0a1D547409D82e1B06618EC284A2CeD";
const xcad = "0x431e0cD023a32532BF3969CddFc002c00E98429d";
const dar = "0x23CE9e926048273eF83be0A3A8Ba9Cb6D45cd978";
const auto = "0xa184088a740c695E156F91f5cC086a06bb78b827";
const avax = "0x1CE0c2827e2eF14D5C4f29a091d735A204794041";
const uni = "0xBf5140A22578168FD562DCcF235E5D43A02ce9B1";
const near = "0x1Fa4a73a3F0133f0025378af00236f3aBDEE5D63";
const bot = "0x1Ab7E7DEdA201E5Ea820F6C02C65Fce7ec6bEd32";
const link = "0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD";
const twt = "0x4B0F1812e5Df2A09796481Ff14017e6005508003";
const bfg = "0x965F527D9159dCe6288a2219DB51fc6Eef120dD1";
const atom = "0x0Eb3a705fc54725037CC9e008bDede697f62F335";
const ghny = "0xa045E37a0D1dd3A45fefb8803D22457abc0A728a";
const etc = "0x3d6545b08693daE087E957cb1180ee38B9e3c25E";
const tmt = "0x4803Ac6b79F9582F69c4fa23c72cb76dD1E46d8d";
const toncoin = "0x76A797A59Ba2C17726896976B7B3747BfD1d220f";
const bat = "0x101d82428437127bF1608F699CD651e6Abf9766E";
const beth = "0x250632378E573c6Be1AC2f97Fcdf00515d0Aa91B";
const bch = "0x8fF795a6F4D97E7887C79beA79aba5cc76444aDf";
const nfty = "0x5774B2fc3e91aF89f89141EacF76545e74265982";
const belt = "0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f";
const c98 = "0xaEC945e04baF28b135Fa7c640f624f8D90F1C3a6";
const chr = "0xf9CeC8d50f6c8ad3Fb6dcCEC577e05aA32B224FE";
const sol = "0x570A5D26f7765Ecb712C0924E4De545B89fD43dF";
const pinks = "0x702b3f41772e321aacCdea91e1FCEF682D21125D";
const pinke = "0x8DA0F18e4deB7Ba81dBD061DF57325a894014B5a";

export const paths = [
    // [pks, wbnb, usdt],
    [pks, wbnb, usdc],
    [pks, wbnb, busd],
    [pks, wbnb, eth],
    [pks, wbnb, btc],

    [pinkswap, wbnb, pinks],
    [pinkswap, wbnb, pinke],
    [pinkswap, wbnb, eth],
    [pinkswap, wbnb, btc],
    [pinkswap, wbnb, busd],
    [pinkswap, wbnb, usdt],
];
