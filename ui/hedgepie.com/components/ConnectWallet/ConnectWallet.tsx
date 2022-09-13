import React, { useEffect, useState } from 'react'
import { Button, Box, ThemeUICSSObject } from 'theme-ui'
import { ArrowRight } from 'react-feather'
import { useWeb3React } from '@web3-react/core'
import useWalletModal from 'widgets/WalletModal/useWalletModal'
import useAuth from 'hooks/useAuth'

import { styles } from './styles'
import toast from 'utils/toast'

const ConnectWallet = (props) => {
  const { isHeaderBtn, dark } = props
  const { login, logout } = useAuth()
  const { account, chainId } = useWeb3React()
  const { onPresentConnectModal } = useWalletModal(login, logout)

  const accountEllipsis = account ? `${account.substring(0, 4)}...${account.substring(account.length - 4)}` : null
  const [chainImg, setChainImg] = useState('')

  useEffect(() => {
    switch (chainId) {
      case 1:
        setChainImg('/images/ethlogo.png')
        break
      case 137:
        setChainImg('/images/polygonlogo.png')
        break
      case 56:
        setChainImg('/images/binancelogo.png')
        break
      default:
        break
    }
  }, [chainId])

  return (
    <>
      {isHeaderBtn ? (
        <Button
          sx={{ ...styles.header_connect_wallet_btn, color: !dark ? '#000' : '#fff' } as ThemeUICSSObject}
          {...props}
        >
          <a href="https://hedgepie.finance" target="_blank">
            {account ? (
              <>
                {accountEllipsis}{' '}
                <img src={chainImg} alt="chain-image" width="40px" height="40px" style={{ marginLeft: '10px' }} />
              </>
            ) : (
              <>
                <Box
                  sx={{
                    marginRight: '9px',
                  }}
                >
                  {'OPEN APP'}
                </Box>
                {/* <ArrowRight /> */}
              </>
            )}
          </a>
        </Button>
      ) : (
        <Button
          sx={styles.non_header_connect_wallet_btn as ThemeUICSSObject}
          onClick={() => toast('Our site will soon be live at hedgepie.finance')}
          {...props}
        >
          {'OPEN APP'}
        </Button>
      )}
    </>
  )
}

export { ConnectWallet }
