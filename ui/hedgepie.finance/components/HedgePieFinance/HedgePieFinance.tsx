import React, { ReactNode } from 'react'
import Head from 'next/head'
import { theme } from 'themes/theme'
import { Box, Image, ThemeProvider } from 'theme-ui'
import { Header } from 'components/Header'
import { TitleMast } from 'components/TitleMast'
import { Footer } from 'components/Footer'

import 'react-toastify/dist/ReactToastify.css'
import { ToastContainer } from 'react-toastify'

type Props = {
  title?: string
  children?: ReactNode
  dark?: boolean
  overlayHeader?: boolean
  isV2?: boolean
}

const HedgePieFinance = (props: Props) => {
  const { title, children, isV2 } = props
  return (
    <ThemeProvider theme={theme}>
      <Box sx={{ backgroundColor: '#F6F7FB' }}>
        <Header dark={props.dark} overlay={props.overlayHeader} />
        {!isV2 && (
          <Image
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: '100%',
              objectPosition: 'right',
              objectFit: 'cover',
              zIndex: -1,
            }}
            src="/images/backdesign.svg"
          />
        )}
        {title && <TitleMast title={title} />}
        <Head>
          <title>Hedge Pie</title>
          <meta name="description" content="Hedge Pie Finance" />
          <link rel="icon" href="/favicon.ico" />
        </Head>
        {children}
        <ToastContainer
          position="bottom-right"
          autoClose={2000}
          hideProgressBar={true}
          newestOnTop={false}
          closeOnClick
          rtl={false}
          pauseOnFocusLoss
          draggable
          pauseOnHover
          icon={false}
          closeButton={true}
        />
        <Footer />
      </Box>
    </ThemeProvider>
  )
}

export default HedgePieFinance
