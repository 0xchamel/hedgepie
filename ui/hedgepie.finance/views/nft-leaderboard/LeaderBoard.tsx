import React, { useEffect, useState } from 'react'
import { Box, ThemeUICSSObject, Spinner } from 'theme-ui'
import LotterySearch from './LotterySearch'
import LotteryTable from './LotteryTable'
import LotteryLoad from './LotteryLoad'

import { useYBNFTMint } from 'hooks/useYBNFTMint'
import { useInvestor } from 'hooks/useInvestor'

import { styles } from './styles'
import toast from 'utils/toast'
import { getBalanceInEther } from 'utils/formatBalance'
import { getPrice } from 'utils/getTokenPrice'

export interface TokenInfo {
  name?: string
  imageURL?: string
  description?: string
  tokenId?: number
  tvl?: string
  totalStaked?: string
  totalParticipants?: number
}

const LeaderBoard = () => {
  const [lotteries, setLotteries] = React.useState([] as TokenInfo[])
  const [searchKey, setSearchKey] = React.useState('')
  const [sortKey, setSortKey] = React.useState('')
  const { getMaxTokenId, getTokenUri } = useYBNFTMint()
  const { getNFTInfo } = useInvestor()

  const [loading, setLoading] = useState(true)

  useEffect(() => {
    setLotteries([])
    const fetchLeaderboardData = async () => {
      setLoading(true)
      const maxTokenId = await getMaxTokenId()
      let tokens = [] as TokenInfo[]
      for (let i = 1; i <= maxTokenId; i++) {
        const tokenUri = await getTokenUri(i)
        // Is the link is invalid, just proceed
        if (!tokenUri.includes('.ipfs.')) {
          continue
        }
        const metadataFile = await fetch(tokenUri)
        console.log('metadataFile' + JSON.stringify(metadataFile))
        if (metadataFile == null) {
          continue
        }

        // Obtain total participants and TVL, Will be used to populate the tvl and participants in the Leaderboard
        const nftInfo = await getNFTInfo(i)
        const bnbPrice = await getPrice('BNB')
        const tvl = bnbPrice ? `$${Number(getBalanceInEther(nftInfo.tvl) * bnbPrice).toFixed(3)} USD` : 'N/A'
        const totalStaked = `${getBalanceInEther(nftInfo.tvl)} BNB`
        const metadata = await metadataFile.json()
        const leaderboardItem = {
          tokenId: i,
          name: metadata.name,
          imageURL: metadata.imageURL,
          description: metadata.description,
          tvl: tvl,
          totalStaked: totalStaked,
          totalParticipants: nftInfo.totalParticipant,
        }
        tokens.push(leaderboardItem)
        setLotteries(tokens)
      }
      setLotteries(tokens)
      console.log('setting loading false')
      setLoading(false)
    }
    fetchLeaderboardData()
  }, [])

  const handleSearch = (key: string) => {
    setSearchKey(key)
  }

  const handleLoad = (data: any) => {
    setLotteries([...lotteries, ...data])
  }

  const handleSort = (key: string) => {
    setSortKey(key === sortKey ? '' : key)
  }

  const filtered = lotteries.filter((d) => {
    return (
      (d.description && d.description.toLowerCase().includes(searchKey.toLowerCase())) ||
      (d.name && d.name.toLowerCase().includes(searchKey.toLowerCase()))
    )
  })

  const sorted = filtered.sort((a: any, b: any) => {
    if (sortKey !== '') {
      return a[sortKey] > b[sortKey] ? 1 : -1
    }
    return 0
  })

  return (
    <Box sx={styles.leaderboard_container as ThemeUICSSObject}>
      <Box sx={styles.leaderboard_inner_container as ThemeUICSSObject}>
        {/* <LotterySearch onSearch={handleSearch} /> */}
        <div
          style={{
            // background: 'linear-gradient(137.62deg, rgba(252, 143, 143, 0.1) 0.17%, rgba(143, 143, 252, 0.3) 110.51%)',
            padding: '20px',
            marginTop: '20px',
          }}
        >
          <LotteryTable data={sorted} onSort={handleSort} sortKey={sortKey} />
          {loading ? (
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0.5rem' }}>
              <Spinner sx={{ color: '#1799DE' }} />
            </Box>
          ) : (
            ''
          )}
        </div>
        {/* <LotteryLoad onLoad={handleLoad} /> */}
      </Box>
    </Box>
  )
}

export default LeaderBoard
