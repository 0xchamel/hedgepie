import React from 'react'
import { Box, Image } from 'theme-ui'
import { components } from 'react-select'

const CustomValue = (props) => {
  const data = props.getValue()[0]

  return (
    <components.ValueContainer {...props}>
      <Box sx={{ height: 0 }}>{props.children}</Box>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          flex: 1,
          userSelect: 'none',
        }}
      >
        {data?.icon && data.icon !== '' ? (
          <Image
            src={data.icon}
            sx={{
              width: 20,
              height: 20,
              [`@media screen and (min-width: 500px)`]: {
                width: 30,
                height: 30,
              },
            }}
          />
        ) : (
          ''
        )}
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            width: 'max-content',
          }}
        >
          <Box
            sx={{
              fontSize: 14,
              fontWeight: 600,
              color: '#0A3F5C',
              ml: 1,
              [`@media screen and (min-width: 500px)`]: {
                fontSize: 15,
                ml: 3,
              },
            }}
          >
            {data.name}
          </Box>
          {/* <Box
            sx={{
              display: 'none',
              color: '#8E8DA0',
              ml: 1,
              [`@media screen and (min-width: 360px)`]: {
                display: 'block',
                fontSize: 12,
              },
              [`@media screen and (min-width: 500px)`]: {
                ml: 3,
                fontSize: 16,
              }
            }}
          >
            {data.description}
          </Box> */}
        </Box>
      </Box>
    </components.ValueContainer>
  )
}

export default CustomValue
