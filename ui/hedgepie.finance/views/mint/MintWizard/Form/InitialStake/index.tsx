import React, { useContext, useEffect, useState } from 'react'
import { Box, Input } from 'theme-ui'
import MintWizardContext from 'contexts/MintWizardContext'
import { useWeb3React } from '@web3-react/core'
import axios from 'axios'
import { getBalanceInEther } from 'utils/formatBalance'
import BigNumber from 'bignumber.js'
import toast from 'utils/toast'

const InitialStake = () => {
  const { formData, setFormData, bnbPrice, ethPrice, maticPrice } = useContext(MintWizardContext)

  const [token, setToken] = useState('')
  const [tokenPrice, setTokenPrice] = useState(0)
  const [bnbBalance, setBNBBalance] = useState(0)

  const [input, setInput] = useState('0')
  const { account, chainId } = useWeb3React()

  useEffect(() => {
    switch (chainId) {
      case 1:
        setToken('ETH')
        setTokenPrice(ethPrice)
        break
      case 137:
        setToken('MATIC')
        setTokenPrice(maticPrice)
        break
      case 56:
        setToken('BNB')
        setTokenPrice(bnbPrice)
        break
      case undefined:
        setToken('BNB')
        setTokenPrice(bnbPrice)
        break
    }
  }, [chainId])

  useEffect(() => {
    // Update the value in USD on change of
    if (formData.initialStake > 0) {
      console.log(formData.initialStake + ' ' + tokenPrice)
      setFormData({
        ...formData,
        valueInUSD: Number(Number(Number(formData.initialStake) * tokenPrice).toFixed(4)),
      })
    }
  }, [tokenPrice, formData.initialStake])

  const handleChange = (e) => {
    if (!account) {
      toast('Please connect your wallet, before entering the initial stake', 'warning')
    }
    if (account && Number.parseFloat(e.target.value) >= bnbBalance) {
      toast('Entered amount is greater than available BNB balance.', 'warning')
    }

    setInput(e.target.value)
    setFormData({
      ...formData,
      initialStake: e.target.value,
      valueInUSD: Number(Number(Number(e.target.value) * tokenPrice).toFixed(4)),
    })
  }

  const getBNBBalance = async () => {
    const balance = await axios.get(
      'https://api.bscscan.com/api?module=account&action=balance&address=' +
        account?.toString() +
        '&apikey=ZWKTR3X6EIE91YMHQ8RNUDHADI1795JXE1',
    )
    const balanceNumber = Number(balance?.data?.result)
    console.log(balanceNumber)
    setBNBBalance(getBalanceInEther(new BigNumber(balanceNumber)))
  }

  useEffect(() => {
    account && getBNBBalance()
  }, [account])

  return (
    <Box
      sx={{
        padding: 3,
        backgroundColor: '#E5F6FF',
        border: '2px solid #BAB9C5',
        background: '#FFFFFF',
        borderRadius: 8,
        [`@media screen and (min-width: 500px)`]: {
          padding: 24,
        },
      }}
    >
      <Box
        sx={{
          fontSize: 16,
          fontWeight: 700,
          color: '#1380B9',
          [`@media screen and (min-width: 500px)`]: {
            fontSize: 24,
          },
        }}
      >
        Initial Stake
      </Box>
      <Box
        sx={{
          fontSize: 12,
          fontWeight: 600,
          color: '#3B3969',
          [`@media screen and (min-width: 500px)`]: {
            fontSize: 16,
          },
        }}
      >
        An Initial Stake on the minted YBNFT
      </Box>
      <Box
        sx={{
          fontSize: 12,
          mt: 22,
          color: '#1A1A1A',
          [`@media screen and (min-width: 500px)`]: {
            fontSize: 16,
            fontWeight: 600,
          },
        }}
      >
        {/* TODO : Update this description */}
        As an owner, when you create an Yield Bearing NFT, you can stake BNB into it.
      </Box>
      <Box
        mt={36}
        sx={{ display: 'flex', flexDirection: ['column', 'column', 'row'], alignItems: 'center', gap: '0.5rem' }}
      >
        <Box
          sx={{
            width: '100%',
            maxWidth: 250,
            height: 62,
            fontWeight: 700,
            backgroundColor: '#fff',
            borderRadius: 8,
            display: 'flex',
            paddingLeft: 24,
            paddingRight: 24,
            color: '#0A3F5C',
            fontSize: 30,
            alignItems: 'center',
            justifyContent: 'center',
            border: '1px solid #E3E3E3',
            background: '#F3F3F3',
          }}
        >
          <Input
            className="performance-input"
            sx={{
              border: 'none',
              outline: 'none',
              padding: 0,
              textAlign: 'right',
              pr: 2,
            }}
            type="number"
            min="0"
            value={input}
            onChange={handleChange}
            onKeyUp={(e) => {
              if (e.key === '-') {
                setInput('0')
                setFormData({
                  ...formData,
                  initialStake: '0',
                  valueInUSD: 0,
                })
              }
            }}
            onWheel={(e) => e.currentTarget.blur()}
          />
          {token}
        </Box>
        {formData.valueInUSD ? (
          <Box sx={{ color: '#0A3F5C', fontSize: 24, fontWeight: 400 }}>${formData.valueInUSD} USD</Box>
        ) : (
          ''
        )}
      </Box>
    </Box>
  )
}

export default InitialStake
