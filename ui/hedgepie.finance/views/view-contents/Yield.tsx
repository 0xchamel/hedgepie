import { useWeb3React } from '@web3-react/core'
import { useInvestor } from 'hooks/useInvestor'
import React, { useEffect, useState } from 'react'
import { Box, Button, Text, ThemeUICSSObject } from 'theme-ui'
import { getBalanceInEther } from 'utils/formatBalance'
import toast from 'utils/toast'
import { styles } from './styles'

function Yield(props: any) {
  const { tokenId } = props
  const { getYield, onYBNFTClaim, getBalance } = useInvestor()
  const [reward, setReward] = useState<undefined | number | string>()
  const [loading, setLoading] = useState(true)
  const [currentStaked, setCurrentStaked] = useState(0)
  const { account } = useWeb3React()

  const handleWithdrawYield = async () => {
    if (!reward || Number(reward) === 0) {
      toast('No reward to claim', 'warning')
      return
    }
    let txHash
    try {
      txHash = await onYBNFTClaim(tokenId)
      toast(`${reward} BNB successfully withdrawn on YBNFT #${tokenId} !!`)
      fetchReward()
    } catch (err) {
      console.log(err)
    }
    console.log(txHash)
  }

  const fetchReward = async () => {
    if (!account || currentStaked === 0) return
    console.log(account)
    setLoading(true)
    try {
      let pendingReward = getBalanceInEther(await getYield(tokenId)).toFixed(2)
      setReward(pendingReward)
    } catch (err) {
      toast('Error while fetching Yield ')
    }
    setLoading(false)
  }

  const setCurrentStakedBalance = async () => {
    let balance = await getBalance(tokenId)
    setCurrentStaked(getBalanceInEther(balance))
  }

  useEffect(() => {
    if (!account || !tokenId) return
    setCurrentStakedBalance()
  }, [account, tokenId])

  useEffect(() => {
    fetchReward()
  }, [account, currentStaked])

  return (
    <>
      {reward !== undefined && currentStaked > 0 ? (
        <Box sx={styles.yield_container as ThemeUICSSObject}>
          <Box sx={styles.yield_inner_container as ThemeUICSSObject}>
            <Text sx={styles.yield_inner_text}>YIELD</Text>
            <Text sx={styles.yield_inner_text}>{reward} BNB</Text>
          </Box>
          {reward > 0 ? (
            <Button sx={styles.withdraw_yield_button as ThemeUICSSObject} onClick={handleWithdrawYield}>
              Claim Yield
            </Button>
          ) : null}
        </Box>
      ) : (
        ''
      )}
    </>
  )
}

export default Yield
