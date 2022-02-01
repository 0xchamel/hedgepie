/* eslint-disable no-use-before-define */
import React from "react"
import type { NextPage } from "next"
import Head from "next/head"

import { Vault } from "components/Vault"
import { HedgePieFinance } from "components/HedgePieFinance"

const VaultPage: NextPage = () => {
  return (
    <div>
      <Head>
        <title>Hedge Pie</title>
        <meta name="description" content="Hedge Pie Finance" />
        <link rel="icon" href="/favicon.ico" />
      </Head>

      <main>
        <HedgePieFinance title="Vault">
          <Vault />
        </HedgePieFinance>
      </main>
    </div>
  )
}

export default VaultPage
