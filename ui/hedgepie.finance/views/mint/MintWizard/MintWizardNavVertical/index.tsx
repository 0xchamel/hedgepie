import React from 'react'
import { Box } from 'theme-ui'
import Label from './Label'
import MintWizardContext from 'contexts/MintWizardContext'

const MintWizardNavVertical = ({ ...props }) => {
  const { wizard } = React.useContext(MintWizardContext)

  return (
    <Box py={20} {...props}>
      <Box>
        {wizard.forms.map((d, i) => (
          <Label key={d} active={wizard.order === i} index={i} label={d} />
        ))}
      </Box>
    </Box>
  )
}

export default MintWizardNavVertical
