import contracts from "../config/contracts.json";

export const lib = { address: (contracts as any).lib };

export const authority = (contracts as any)?.authority;

export const adapters = {
    autofarm: [
        [
            619,
            "0x0895196562C7868C5Be92459FaE7f877ED450452",
            "0xcFF7815e0e85a447b0C21C94D25434d1D0F718D1",
            "0x0ed7e52944161450477ee417de9cd3a859b14fd0",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "AutoFarm::Vault::WBNB-CAKE",
            authority,
        ],
        [
            620,
            "0x0895196562C7868C5Be92459FaE7f877ED450452",
            "0x06af474aa7fF6862ffF27a239459cc58d95884a8",
            "0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "AutoFarm::Vault::WBNB-BUSD",
            authority,
        ],
        [
            621,
            "0x0895196562C7868C5Be92459FaE7f877ED450452",
            "0x302dD3ebB6D554E8D16A7E3eb2985E76Fe408FA8",
            "0x28415ff2C35b65B9E5c7de82126b4015ab9d031F",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "AutoFarm::Vault::ADA-WBNB",
            authority,
        ],
        [
            622,
            "0x0895196562C7868C5Be92459FaE7f877ED450452",
            "0xb726dFe75835F132613Bb25638Dc89a6Db09Ec73",
            "0xDd5bAd8f8b360d76d12FdA230F8BAF42fe0022CF",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "AutoFarm::Vault::DOT-WBNB",
            authority,
        ],
        [
            628,
            "0x0895196562C7868C5Be92459FaE7f877ED450452",
            "0x63847419C978190712769F56CF8bA72347C3fB11",
            "0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "AutoFarm::Vault::BTCB-WBNB",
            authority,
        ],
    ],
    biswap: [
        [
            0,
            "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x0000000000000000000000000000000000000000",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Biswap::Farm::BSW",
            authority,
        ],
        [
            9,
            "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739",
            "0x2b30c317ceDFb554Ec525F85E79538D59970BEb0",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Biswap::Farm::USDT-BSW",
            authority,
        ],
        [
            10,
            "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739",
            "0x46492b26639df0cda9b2769429845cb991591e0a",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Biswap::Farm::BSW-BNB",
            authority,
        ],
        [
            25,
            "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739",
            "0x52a499333a7837a72a9750849285e0bb8552de5a",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Biswap::Farm::FIL-USDT",
            authority,
        ],
        [
            2,
            "0xDbc1A13490deeF9c3C12b44FE77b503c1B061739",
            "0x8840C6252e2e86e545deFb6da98B2a0E26d8C1BA",
            "0x965f527d9159dce6288a2219db51fc6eef120dd1",
            "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Biswap::Farm::USDT-WBNB",
            authority,
        ],
    ],
    beefy: [
        [
            "0x164fb78cAf2730eFD63380c2a645c32eBa1C52bc",
            "0xDA8ceb724A06819c0A5cDb4304ea0cB27F8304cF",
            "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Beefy::Vault::Biswap USDT-BUSD",
            authority,
        ],
        [
            "0xb26642B6690E4c4c9A6dAd6115ac149c700C7dfE",
            "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Beefy::Vault::PancakeSwap CAKE-BNB",
            authority,
        ],
    ],
    belt: [
        [
            "0x9171Bf7c050aC8B4cf7835e51F7b4841DFB2cCD0",
            "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
            "0x9171Bf7c050aC8B4cf7835e51F7b4841DFB2cCD0",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Belt::Vault::BUSD",
            authority,
        ],
        [
            "0x55E1B1e49B969C018F2722445Cd2dD9818dDCC25",
            "0x55d398326f99059fF775485246999027B3197955",
            "0x55E1B1e49B969C018F2722445Cd2dD9818dDCC25",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Belt::Vault::USDT",
            authority,
        ],
        [
            "0x51bd63F240fB13870550423D208452cA87c44444",
            "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
            "0x51bd63F240fB13870550423D208452cA87c44444",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Belt::Vault::BTC",
            authority,
        ],
    ],
    pksFarm: [
        [
            2,
            "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652",
            "0x0eD7e52944161450477ee417DE9Cd3a859b14fD0",
            "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Farm::CAKE-WBNB",
            authority,
        ],
        [
            3,
            "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652",
            "0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16",
            "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Farm::BUSD-WBNB",
            authority,
        ],
        [
            10,
            "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652",
            "0x74E4716E431f45807DCF19f284c7aA99F18a4fbc",
            "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Farm::ETH-WBNB",
            authority,
        ],
        [
            11,
            "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652",
            "0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082",
            "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Farm::BTCB-WBNB",
            authority,
        ],
    ],
    pksStake: [
        [
            "0xDe9FC6485b5f4A1905d8011fcd201EB78CF34073",
            "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82",
            "0xCfFD4D3B517b77BE32C76DA768634dE6C738889B",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Stake::ARENA",
            authority,
        ],
        [
            "0x3B48325b7CA831ca7D5b649B074fF697c66166c3",
            "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82",
            "0x7e9AB560d37E62883E882474b096643caB234B65",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Stake::CHAMP",
            authority,
        ],
        [
            "0x08C9d626a2F0CC1ed9BD07eBEdeF8929F45B83d3",
            "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82",
            "0x724A32dFFF9769A0a0e1F0515c0012d1fB14c3bd",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "PKS::Stake::SQUAD",
            authority,
        ],
    ],
    alpacaLend: [
        [
            "0x7C9e73d4C71dae564d41F78d56439bB4ba87592f",
            "0xe9e7cea3dedca5984780bafc599bd69add087d56",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Alpaca::Lend::BUSD",
            authority,
        ],
        [
            "0xbfF4a34A4644a113E8200D7F1D79b3555f723AfE",
            "0x2170ed0880ac9a755fd29b2688956bd959f933f8",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Alpaca::Lend::ETH",
            authority,
        ],
        [
            "0xf1bE8ecC990cBcb90e166b71E368299f0116d421",
            "0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Alpaca::Lend::ALPACA",
            authority,
        ],
        [
            "0x158Da805682BdC8ee32d52833aD41E74bb951E59",
            "0x55d398326f99059ff775485246999027b3197955",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Alpaca::Lend::USDT",
            authority,
        ],
        [
            "0x800933D685E7Dc753758cEb77C8bd34aBF1E26d7",
            "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Alpaca::Lend::USDC",
            authority,
        ],
    ],
    venusLend: [
        [
            "0x95c78222B3D6e262426483D42CfA53685A67Ab9D",
            "0x2a914D534715F1A84205fb05d1dc8281F8da6540",
            "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
            "0x95c78222B3D6e262426483D42CfA53685A67Ab9D",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Venus::Lend::BUSD",
            authority,
        ],
        [
            "0x86aC3974e2BD0d60825230fa6F355fF11409df5c",
            "0x2a914D534715F1A84205fb05d1dc8281F8da6540",
            "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
            "0x86aC3974e2BD0d60825230fa6F355fF11409df5c",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Venus::Lend::CAKE",
            authority,
        ],
        [
            "0x61eDcFe8Dd6bA3c891CB9bEc2dc7657B3B422E93",
            "0x2a914D534715F1A84205fb05d1dc8281F8da6540",
            "0x85EAC5Ac2F758618dFa09bDbe0cf174e7d574D5B",
            "0x61eDcFe8Dd6bA3c891CB9bEc2dc7657B3B422E93",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Venus::Lend::TRX",
            authority,
        ],
    ],
    apeswapLend: [
        [
            "0x34878F6a484005AA90E7188a546Ea9E52b538F6f",
            "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Apeswap::Lend::BNB",
            authority,
        ],
        [
            "0x3353f5bcfD7E4b146F2eD8F1e8D875733Cd754a7",
            "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Apeswap::Lend::CAKE",
            authority,
        ],
        [
            "0xdBFd516D42743CA3f1C555311F7846095D85F6Fd",
            "0x55d398326f99059fF775485246999027B3197955",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Apeswap::Lend::USDT",
            authority,
        ],
        [
            "0x0096B6B49D13b347033438c4a699df3Afd9d2f96",
            "0xe9e7cea3dedca5984780bafc599bd69add087d56",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Apeswap::Lend::BUSD",
            authority,
        ],
        [
            "0xC2E840BdD02B4a1d970C87A912D8576a7e61D314",
            "0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95",
            "0x10ED43C718714eb63d5aA57B78B54704E256024E",
            "Apeswap::Lend::BANANA",
            authority,
        ],
    ],
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
    ],
};

export const adapterNames = {
    autofarm: "AutoVaultAdapterBsc",
    biswap: "BiSwapFarmLPAdapterBsc",
    beefy: "BeefyVaultAdapterBsc",
    belt: "BeltVaultAdapterBsc",
    pksFarm: "PancakeSwapFarmLPAdapterBsc",
    pksStake: "PancakeStakeAdapterBsc",
    alpacaLend: "AlpacaLendAdapterBsc",
    apeswapLend: "ApeswapLendAdapterBsc",
    venusLend: "VenusLendAdapterBsc",
    radiant: "RadiantV2Bsc",
};

export const adapterPaths = {
    autofarm: "contracts/strategies/autofarm/auto-vault-adapter.sol:AutoVaultAdapterBsc",
    biswap: "contracts/strategies/biswap/biswap-farm-adapter.sol:BiSwapFarmLPAdapterBsc",
    beefy: "contracts/strategies/beefy/beefy-vault-adapter.sol:BeefyVaultAdapterBsc",
    belt: "contracts/strategies/belt/belt-vault-adapter.sol:BeltVaultAdapterBsc",
    pksFarm: "contracts/strategies/pancakeswap/pancake-farm-adapter.sol:PancakeSwapFarmLPAdapterBsc",
    pksStake: "contracts/strategies/pancakeswap/pancake-stake-adapter.sol:PancakeStakeAdapterBsc",
    alpacaLend: "contracts/strategies/alpaca/alpaca-lend-adapter.sol:AlpacaLendAdapterBsc",
    apeswapLend: "contracts/strategies/apeswap/apeswap-lend-adapter.sol:ApeswapLendAdapterBsc",
    venusLend: "contracts/strategies/venus/venus-lend-adapter.sol:VenusLendAdapterBsc",
    radiant: "contracts/strategies/venus/radiant-v2-adapter.sol:RadiantV2Bsc",
};

const pks = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
const biswap = "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8";

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

export const paths = [
    [pks, wbnb, usdt],
    [pks, wbnb, usdc],
    [pks, wbnb, busd],
    [pks, wbnb, eth],
    [pks, wbnb, cake],
    [pks, wbnb, ada],
    [pks, wbnb, dot],
    [pks, wbnb, btc],
    [pks, wbnb, bsw],
    [pks, wbnb, fil],
    [pks, wbnb, busd, trx],
    [pks, wbnb, cake, arena],
    [pks, wbnb, busd, champ],
    [pks, wbnb, cake, squad],
    [pks, wbnb, xvs],
    [pks, wbnb, rdnt],
    [biswap, wbnb, usdt],
    [biswap, wbnb, bsw],
    [biswap, wbnb, fil],
];
