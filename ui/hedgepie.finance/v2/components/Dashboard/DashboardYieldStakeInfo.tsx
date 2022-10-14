import { useInvestor } from 'hooks/useInvestor'
import { useYBNFTMint } from 'hooks/useYBNFTMint'
import React, { useState, useEffect } from 'react'
import { Box, Text } from 'theme-ui'
import { getBalanceInEther } from 'utils/formatBalance'
import { getPrice } from 'utils/getTokenPrice'
import YieldStakeDoughnut from './YieldStakeDoughnut'

type Tab = 'yield' | 'stake'
function DashboardYieldStakeInfo() {
  const [activeTab, setActiveTab] = useState<Tab>('yield')
  const [instruments, setInstruments] = useState<any>([])
  const [yields, setYields] = useState<{ title: string; value: number; color: string }[]>([])
  const [stakes, setStakes] = useState<{ title: string; value: number; color: string }[]>([])
  const [totalYield, setTotalYield] = useState<number>()
  const [totalStake, setTotalStake] = useState<number>()
  const [invested, setInvested] = useState<number[]>([])
  const { getYield, getBalance } = useInvestor()
  const { getMaxTokenId, getTokenUri } = useYBNFTMint()
  const [chartData, setChartData] = useState<any>({})
  const [bnbPrice, setBNBPrice] = useState<number>(0)

  useEffect(() => {
    const fetchAndSetBNBPrice = async () => {
      const price = await getPrice('BNB')
      price && setBNBPrice(price)
    }
    fetchAndSetBNBPrice()
  }, [])

  // START - Fetch and Store Yields

  // START - Get indices of invested tokens
  useEffect(() => {
    const getInvestedFunds = async () => {
      let investedData: number[] = []
      const maxTokenId = await getMaxTokenId()
      for (let i = 1; i <= maxTokenId; i++) {
        const investedInToken = await getBalance(i)
        if (getBalanceInEther(investedInToken) !== getBalanceInEther(0)) {
          investedData.push(i)
        }
      }
      setInvested(investedData)
    }
    getInvestedFunds()
  }, [])
  // END - Get indices of invested tokens

  useEffect(() => {
    const fetchAndStoreYields = async () => {
      let stakesArr: any[] = []
      let yieldsArr: any[] = []
      let rewardTot = 0
      let stakeTot = 0
      for (let index = 0; index < invested.length; index++) {
        const i = invested[index]
        const bnbPrice = await getPrice('BNB')
        const stake = await getBalance(i)
        const reward = await getYield(i)
        const tokenUri = await getTokenUri(i)
        if (!tokenUri.includes('.ipfs.')) {
          return
        }
        let metadataFile: any = undefined
        try {
          metadataFile = await fetch(tokenUri)
        } catch (err) {
          return
        }
        const metadata = await metadataFile.json()
        let stakeObj = {
          color: 'blue',
          title: metadata.name,
          value: `$${bnbPrice ? getBalanceInEther(bnbPrice * stake).toFixed(5) : 0.0} USD`,
        }
        stakeTot = stakeTot + Number(stake)
        stakesArr.push(stakeObj)
        let yieldObj = {
          color: 'blue',
          title: metadata.name,
          value: `$${bnbPrice ? getBalanceInEther(bnbPrice * reward).toFixed(5) : 0.0} USD`,
        }
        rewardTot = rewardTot + Number(reward)
        console.log('reward ' + reward)
        console.log('rewardTot ' + rewardTot)

        yieldsArr.push(yieldObj)
      }
      await setStakes(stakesArr)
      await setYields(yieldsArr)
      console.log('ajshd' + JSON.stringify(yieldsArr))
      await setTotalStake(stakeTot)
      await setTotalYield(getBalanceInEther(rewardTot))

      console.log('TOTAL REWARD:' + JSON.stringify(totalStake && bnbPrice ? totalStake * bnbPrice : ''))
    }
    fetchAndStoreYields()
  }, [])
  // END - Fetch and Store Yields

  return (
    <Box
      sx={{
        backgroundColor: '#FFFFFF',
        borderRadius: '16px',
        boxShadow: '-1px 1px 8px 2px rgba(0, 0, 0, 0.1)',
        width: '100%',
        minHeight: '20rem',
        padding: '1.5rem 1.5rem 1.5rem 1.5rem',
        display: 'flex',
        flexDirection: 'column',
        gap: '15px',
      }}
    >
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'row',
          alignItems: 'center',
          width: '100%',
          gap: '20px',
          height: '20rem',
        }}
      >
        {/* Tabs View */}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '10px', flex: 1, height: '100%' }}>
          <Box sx={{ display: 'flex', flexDirection: 'row', gap: '0px', alignItems: 'center' }}>
            <Box
              sx={{
                color: activeTab === 'yield' ? '#1799DE' : '#000000',
                borderBottom: activeTab === 'yield' ? '2px solid #1799DE' : '2px solid #D9D9D9',
                cursor: 'pointer',
                fontFamily: 'Inter',
                padding: '1rem',
              }}
              onClick={() => {
                setActiveTab('yield')
              }}
            >
              <Text sx={{ fontSize: '16px', fontFamily: 'Inter', fontWeight: '600' }}>Total Yield</Text>
            </Box>
            <Box
              sx={{
                color: activeTab === 'stake' ? '#1799DE' : '#000000',
                borderBottom: activeTab === 'stake' ? '2px solid #1799DE' : '2px solid #D9D9D9',
                cursor: 'pointer',
                fontFamily: 'Inter',
                padding: '1rem',
              }}
              onClick={() => {
                setActiveTab('stake')
              }}
            >
              <Text sx={{ fontSize: '16px', fontFamily: 'Inter', fontWeight: '600' }}>Total Staked</Text>
            </Box>
          </Box>
          <Box sx={{ width: '100%', height: '100%', padding: '0.5rem' }}>
            {activeTab === 'yield' && (
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                  <Text sx={{ fontFamily: 'Inter', fontSize: '24px', fontWeight: '700', color: '#000000' }}>
                    {totalYield && bnbPrice * totalYield}
                    {`$${bnbPrice && totalYield ? (bnbPrice * totalYield).toFixed(4) : '0.0'} USD`}
                  </Text>
                  {/* <Text sx={{ fontFamily: 'Inter', fontSize: '10px', fontWeight: '700', color: '#4F4F4F' }}>
                    10th Aug - 19th Sept, 2022
                  </Text> */}
                </Box>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {yields.map((i) => (
                    <Box sx={{ display: 'flex', flexDirection: 'row', gap: '10px', alignItems: 'center' }}>
                      <Box sx={{ width: '10px', height: '10px', backgroundColor: i.color, borderRadius: '60px' }}></Box>
                      <Text sx={{ fontFamily: 'Inter', fontSize: '16px', fontWeight: '600' }}>{i.title}</Text>
                      <Text sx={{ fontFamily: 'Inter', fontSize: '14px', fontWeight: '400' }}>{i.value}</Text>
                    </Box>
                  ))}
                </Box>
              </Box>
            )}
            {activeTab === 'stake' && (
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                  <Text sx={{ fontFamily: 'Inter', fontSize: '24px', fontWeight: '700', color: '#000000' }}>
                    $24,245.13
                  </Text>
                  {/* <Text sx={{ fontFamily: 'Inter', fontSize: '10px', fontWeight: '700', color: '#4F4F4F' }}>
                    10th Aug - 19th Sept, 2022
                  </Text> */}
                </Box>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {stakes.map((i) => (
                    <Box sx={{ display: 'flex', flexDirection: 'row', gap: '10px', alignItems: 'center' }}>
                      <Box sx={{ width: '10px', height: '10px', backgroundColor: i.color, borderRadius: '60px' }}></Box>
                      <Text sx={{ fontFamily: 'Inter', fontSize: '16px', fontWeight: '600' }}>{i.title}</Text>
                      <Text sx={{ fontFamily: 'Inter', fontSize: '14px', fontWeight: '400' }}>{i.value}</Text>
                    </Box>
                  ))}
                </Box>
              </Box>
            )}
          </Box>
        </Box>
        <Box
          sx={{
            display: 'flex',
            flex: 1,
            alignItems: 'center',
            justifyContent: 'center',
            width: '100%',
            height: '100%',
          }}
        >
          <YieldStakeDoughnut data={chartData} />
        </Box>
      </Box>
    </Box>
  )
}

export default DashboardYieldStakeInfo
