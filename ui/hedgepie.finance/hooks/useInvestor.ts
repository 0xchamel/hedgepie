import { useCallback, useRef } from 'react'
import { useWeb3React } from '@web3-react/core'
import { useInvestorContract, useWBNBContract } from 'hooks/useContract'
import {
  depositOnYBNFT,
  depositBNBOnYBNFT,
  withdrawFromYBNFT,
  withdrawBNBFromYBNFT,
  approveToken,
  fetchAllowance,
  fetchBalance,
  fetchYield,
  claimFromYBNFT,
  fetchNFTInfo,
  fetchParticipants
} from 'utils/callHelpers/binance/Investor'
import { getBalanceAmount } from 'utils/formatBalance'

export const useInvestor = () => {
  const { account } = useWeb3React()
  const investorContract = useInvestorContract()
  const wBNBContract = useWBNBContract()

  const handleDeposit = useCallback(
    async (ybnftId, amount) => {
      // const txHash = await depositOnYBNFT(investorContract, account, ybnftId, token, amount)
      const txHash = await depositBNBOnYBNFT(investorContract, account, ybnftId, amount)
      console.info(txHash)
    },
    [account, investorContract],
  )

  const handleWithdraw = useCallback(
    async (ybnftId) => {
      // const txHash = await withdrawFromYBNFT(investorContract, account, ybnftId, token)
      const txHash = await withdrawBNBFromYBNFT(investorContract, account, ybnftId)
      console.info(txHash)
    },
    [account, investorContract],
  )

  const handleClaim = useCallback(
    async (ybnftId) => {
      // const txHash = await withdrawFromYBNFT(investorContract, account, ybnftId, token)
      const txHash = await claimFromYBNFT(investorContract, account, ybnftId)

      console.info(txHash)
    },
    [account, investorContract],
  )

  const handleApprove = useCallback(async () => {
    const txHash = await approveToken(wBNBContract, investorContract, account)
    console.info(txHash)
  }, [account, investorContract])

  const getAllowance = useCallback(async () => {
    const allowance = await fetchAllowance(wBNBContract, account)
    return allowance
  }, [account, investorContract])

  const getBalance = useCallback(
    async (ybnftId) => {
      
      const balance = await fetchBalance(investorContract, account, ybnftId)
      return balance
    },
    [account, investorContract],
  )

  const getYield = useCallback(
    async (ybnftId) => {
      console.log("token::"+ybnftId)
      const reward = await fetchYield(investorContract, account, ybnftId)
      return reward
    },
    [account, investorContract],
  )

  const getNFTInfo = useCallback(
    async (ybnftId) => {
      const nftInfo = await fetchNFTInfo(investorContract, ybnftId)
      return nftInfo
    },
    [account, investorContract],
  )

  
  const getTotalParticipants = useCallback(
    async (ybnftId) => {
      const participants = await fetchParticipants(investorContract, ybnftId)
      return participants
    },
    [account, investorContract],
  )

  return {
    onYBNFTDeposit: handleDeposit,
    onYBNFTWithdraw: handleWithdraw,
    onYBNFTInvestorApprove: handleApprove,
    getAllowance: getAllowance,
    getBalance: getBalance,
    getYield: getYield,
    getNFTInfo: getNFTInfo,
    getTotalParticipants:getTotalParticipants,
    onYBNFTClaim: handleClaim
  }
}
