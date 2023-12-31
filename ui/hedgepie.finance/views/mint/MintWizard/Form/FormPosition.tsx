import React from 'react'
import { Box, Button } from 'theme-ui'
import MintWizardContext from 'contexts/MintWizardContext'
import PositionList from './PositionList'
import YbNftSummaryChart from './YbNftSummaryChart'
import toast from 'utils/toast'
import { ArrowLeft } from 'react-feather'

const FormPosition = () => {
  const { wizard, setWizard, formData, account } = React.useContext(MintWizardContext)

  const duplicatesInPositions = (positions) => {
    let positionNames = [] as any[]
    let hasDuplicates = false
    positions.forEach((position) => {
      if (
        positionNames.filter(
          (p) =>
            JSON.stringify(p) === JSON.stringify({ protocol: position?.composition?.name, pool: position?.pool?.name }),
        ).length
      ) {
        hasDuplicates = true
      } else {
        positionNames.push({ protocol: position?.composition?.name, pool: position?.pool?.name })
      }
    })
    return hasDuplicates
  }

  const ifTotalNotHundred = (positions) => {
    let total = 0
    for (let position of positions) {
      total = total + parseFloat(position.weight)
    }
    if (total !== 100) {
      return true
    }
    return false
  }

  const checkIfPositionsEmpty = () => {
    formData.positions.forEach((p) => {
      if (p.composition) {
        if (p.composition.name === 'Protocol' || !p.composition.pools?.length) return true
      }
    })
    return false
  }

  const handleNext = () => {
    if (checkIfPositionsEmpty()) {
      toast('Cannot proceed with empty positions !!', 'warning')
      return
    }
    if (formData.positions && (duplicatesInPositions(formData.positions) || ifTotalNotHundred(formData.positions))) {
      toast('Make sure the total is 100% and There are no duplicates !!', 'warning')
      return
    }
    if (!account) {
      toast('Please connect your wallet to continue !!')
      return
    }
    setWizard({
      ...wizard,
      order: 2,
    })
  }

  const handleBack = () => {
    setWizard({
      ...wizard,
      order: 0,
    })
  }

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: '34px',
        marginTop: 40,
        [`@media screen and (min-width: 1200px)`]: {
          flexDirection: 'row',
        },
      }}
    >
      <Box
        sx={{
          flex: 1,
        }}
      >
        <PositionList />
        <Box mt={24} sx={{ display: 'flex', flexDirection: 'row', gap: '20px' }}>
          <Button
            variant="primary"
            sx={{
              height: 64,
              border: '1px solid #BAB9C5',
              borderRadius: 6,
              padding: 0,
              cursor: 'pointer',
              transition: 'all .2s',
              fontSize: '20px',
              display: 'flex',
              flexDirection: 'row',
              gap: '10px',
              alignItems: 'center',
              justifyContent: 'center',
              width: '100%',
              backgroundColor: '#FFFFFF',
              color: '#1A1A1A',
              fontWeight: '600',
            }}
            onClick={handleBack}
          >
            <ArrowLeft />
            Back
          </Button>
          <Button
            variant="primary"
            sx={{
              height: 64,
              width: '100%',
              borderRadius: 6,
              padding: 0,
              cursor: 'pointer',
              transition: 'all .2s',
              fontSize: '20px',
              background: 'linear-gradient(333.11deg, #1799DE -34.19%, #E98EB3 87.94%)',
            }}
            onClick={handleNext}
          >
            Next Step
          </Button>
        </Box>
      </Box>
      <Box
        sx={{
          maxWidth: 334,
          flexShrink: 0,
        }}
      >
        <YbNftSummaryChart />
      </Box>
    </Box>
  )
}

export default FormPosition
