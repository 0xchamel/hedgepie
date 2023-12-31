import { useWeb3React } from '@web3-react/core'
import { ConnectWallet } from 'components/ConnectWallet'
import useAuth from 'hooks/useAuth'
import React, { useEffect } from 'react'
import { Box, Button, Text } from 'theme-ui'
import { useWalletModal } from 'widgets/WalletModal'
import DashboardFunds from './DashboardFunds'
import DashboardInvestments from './DashboardInvestments'
import DashboardOverview from './DashboardOverview'
import DashboardYieldStakeInfo from './DashboardYieldStakeInfo'

function DashboardInfo() {
  const { account } = useWeb3React()
  const { login, logout } = useAuth()
  const { onPresentConnectModal } = useWalletModal(login, logout)

  return (
    <>
      {account ? (
        <Box
          sx={{
            margin: ['0.5rem 1rem', '2rem 3rem', '2rem 3rem', '2rem 3rem'],
            width: '100%',
            display: 'flex',
            flexDirection: 'column',
            gap: '20px',
          }}
        >
          <DashboardOverview />
          <DashboardFunds />
          <DashboardInvestments />
          <DashboardYieldStakeInfo />
        </Box>
      ) : (
        <Box
          sx={{
            height: '20rem',
            width: '100%',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '20px',
          }}
        >
          <Text sx={{ fontFamily: 'Plus Jakarta Sans', fontSize: '20px', color: '#14114B', fontWeight: '600' }}>
            Please connect wallet to access your Funds and Investments 🎉
          </Text>
          <Button
            sx={{
              padding: '10px',
              fontSize: '20px',
              fontFamily: 'Plus Jakarta Sans',
              background: 'linear-gradient(333.11deg, #1799DE -34.19%, #E98EB3 87.94%)',
              cursor: 'pointer',
            }}
            onClick={onPresentConnectModal}
          >
            Connect Wallet
          </Button>
        </Box>
      )}
    </>
  )
}

export default DashboardInfo
