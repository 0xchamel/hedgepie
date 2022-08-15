export const styles = {
  flex_outer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  flex_container: {
    width: '75rem',
    marginTop: '-3rem',
    // boxShadow: '0px 25px 55px rgba(209, 208, 219, 0.4)',
    flexDirection: 'column',
  },
  flex_inner_container: {
    margin: '1rem',
    flexDirection: 'column',
    backgroundColor: '#E5F6FF',
    borderRadius: '6px',
    width: '80%',
    padding: '0rem 3rem',
    paddingBottom: '5rem',
  },
  title: {
    height: '7rem',
    alignItems: 'center',
    paddingLeft: '2rem',
    backgroundColor: '#14114B',
    color: '#fff',
    fontWeight: '500',
    fontFamily: 'Noto Sans',
    borderRadius:'32px',
    fontSize: '28px',
  },
  flex_start_container: { flexDirection:'column',alignItems: 'flex-start', justifyContent: 'flex-start', padding: '40px', gap: '30px', marginTop:"30px", borderRadius:'32px', boxShadow:'0px -2px 20px rgba(0, 0, 0, 0.1), 0px 25px 55px rgba(209, 208, 219, 0.4);',backgroundColor:'#fff' },
  flex_start_inner_container: { width: '100%', flexDirection: 'column', gap: '2rem' },
  flex_nft_name_container: { flexDirection: 'row', gap: '0.5rem', backgroundColor:'#F2F9FD', borderRadius:'16px', padding:'1rem' },
  flex_column: { flexDirection: 'column', gap:'0.5rem' },
  series_name_text: { color: '#8988A5', fontSize: '16px', fontWeight: '600', letterSpacing:'0.15rem' },
  nft_name_text: { color: '#14114B', fontWeight: '360', fontSize: '32px', fontFamily:'Noto Sans', lineHeight:'32px' },
  nft_desc_text: { color: '#8E8DA0', fontSize: '16px', paddingLeft: 'px' },
  flex_badges_row: { flexDirection: 'row', gap: '30px' },
  flex_badge_container: {
    justifyContent: 'center',
    alignItems: 'center',
    gap: '0.3rem',
  },
  badge_title_text: { color: '#0B4C6F',lineHeight:'14px', fontFamily:'Noto Sans', fontSize:'16px' },
  badge_value_text: { color: '#0B4C6F',lineHeight:'14px', fontFamily:'Noto Sans',fontSize:'16px' },
  flex_strategy_container: {
    backgroundColor:'#F2F9FD',
    flexDirection: 'column',
    borderRadius: '10px',
    padding: '20px',
    gap: '20px',
    width:'70%'
  },
  strategy_title_text: { fontWeight: '600', fontSize: '22px', color:'#16103A',lineHeight:'24px' },
  flex_strategy_inner_container: { gap: '15px', flexWrap: 'wrap' },
  flex_strategy_details_container: {
    backgroundColor: '#D1EBF8',
    borderRadius: '8px',
    width: 'fit-content',
    height: '100px',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '10px',
    padding: '10px',
  },
  strategy_detail_image: { width: '50px', height: '50px' },
  flex_strategy_detail_column: { flexDirection: 'column', gap: '5px' },
  strategy_detail_quantity_text: { fontWeight: '600', fontSize: '22px', color: '#0B4C6F' },
  strategy_detail_value_text: { color: '#8E8DA0', fontSize: '14px', fontWeight: '500' },
  strategy_detail_apy_text: { color: '#8988A5', fontFamily: 'Noto Sans', fontWeight: '600', fontSize: '16px' },
  flex_right_container: { flexDirection: 'column', width: '30rem', gap: '1rem' },
  flex_owner_details_container: {
    flexDirection: 'row',
    gap: '10px',
    alignItems: 'center',
    marginLeft: 'auto',
  },
  owner_name_text: { fontSize: '20px', fontWeight: '700', color: '#ABABAB' },
  owner_image: { width: '120px', height: '120px', borderRadius:'300px', marginRight:'10px' },
  flex_staking_details: { alignItems: 'center', justifyContent: 'center', gap: '1rem', flexDirection: 'column',padding:'0 0rem 0 1rem' },
  staking_sub_title_text: { fontFamily: 'Noto Sans', fontSize: '20px', fontWeight: '600', color: '#FD5298' },
  unstake_button: {
    backgroundColor: '#FD5298',
    border: '4px solid #fff',
    borderRadius: '8px',
    color: '#fff',
    fontFamily: 'Noto Sans',
    height: '3rem',
    width: '100%',
    fontWeight: '600',
    ':hover': {
      backgroundColor: '#fff',
      color:'#FD5298',
      cursor: 'pointer',
      opacity: 0.8,
    },
  },
  withdraw_yield_button: {
    backgroundColor: '#fff',
    border: '2px solid #e3bc20',
    borderRadius: '50px',
    color: '#e3bc20',
    fontFamily: 'Noto Sans',
    height: '3rem',
    width: '100%',
    fontWeight: '600',
    ':hover': {
      backgroundColor: '#fff',
      cursor: 'pointer',
      opacity: 0.7,
    },
  },
  flex_details_container: {
    flexDirection: 'row',
    gap: '1rem',
    alignSelf: 'flex-start',
    marginLeft: '1rem',
    width: '100%',
  },
  details_title_text: { fontSize: '16px', fontWeight: '600', fontFamily: 'Noto Sans', color: '#8E8DA0' },
  flex_inner_details_container: {
    backgroundColor: '#F5F5F5',
    flexDirection: 'column',
    gap: '0.2rem',
    padding: '0.2rem',
    width: '15rem',
    textOverflow: 'ellipsis',
    whiteSpace:'initial'
  },
  inner_details_title_text: {
    color: '#0B4C6F',
    fontFamily: 'Noto Sans',
    fontStyle: 'normal',
    fontWeight: 600,
    fontSize: '16px',
    lineHeight: '150%',
  },
  inner_details_value_text: {
    color: '#8E8DA0',
    fontFamily: 'Noto Sans',
    fontStyle: 'normal',
    fontWeight: 600,
    fontSize: '16px',
    lineHeight: '150%',
    whiteSpace:'initial'
  },
  div_button_input: {
    position: 'relative',
    width: '100%',
    overflow: 'hidden',
    marginBottom: '10px',
    backgroundColor: '#E5F6FF',
    borderRadius: '31px',
  },
  flex_button_badge: { position: 'absolute', marginTop: 0, height: '100%', gap: '10px', zIndex: '1' },
  stake_button: {
    position: 'relative',
    height: '100%',
    borderRadius: '40px',
    width: '200px',
    padding: '0px 20px',
    lineHeight: '48px',
    fontSize: '18px',
    fontWeight: '600',
    opacity: '0.8',
    backgroundColor: '#1799DE',
    color: '#fff',
    cursor: 'pointer',
    ':hover': {
      border: '2px solid rgb(157 83 182)',
      color: 'rgb(157 83 182)',
    },
  },
  max_badge: {
    width: 'fit-content',
    height: 'fit-content',
    alignSelf: 'center',
    backgroundColor: 'rgba(160, 160, 160, 0.32)',
    borderRadius: '4px',
    color: '#8E8DA0',
    fontWeight: '300',
  },
  stake_input: {
    position: 'relative',
    height: '56px',
    borderRadius: '30px',
    minWidth: '30rem',
    boxShadow: 'none',
    border: 'none',
    outline: 0,
    fontSize: '18px',
    paddingRight: '5rem',
    textAlign: 'right',
    fontWeight: '600',
    color: '#8E8DA0',
  },

  vault_container: {
    backgroundColor: '#E5F6FF',
    borderRadius: 12,
    maxWidth: 556,
    margin: '0 auto',
  },
  vault_form_tab: {
    width: '50%',
    borderRadius: 12,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all .2s',
    userSelect: 'none',
  },
  vault_action_button: {
    backgroundColor:'#fff',
    color:'#DF4886',
    fontWeight:'600',
    height: 50,
    borderRadius: 8,
    cursor: 'pointer',
    width: '100%',
    ':hover': {
      backgroundColor: '#DF4886',
      color:'#FFF',
      cursor: 'pointer',
      opacity: 0.8,
    },
  },
  vault_action_button_container_mobile: {
    display: 'block',
    marginBottom: 2,
    width: '100%',
    [`@media screen and (min-width: 600px)`]: {
      display: 'none',
    },
  },
  vault_action_max_button: {
    width: 44,
    height: 26,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(160, 160, 160, 0.32)',
    borderRadius: '4px',
    color: '#8E8DA0',
    flexShrink: 0,
    margin: '0 8px 0 32px',
    [`@media screen and (min-width: 600px)`]: {
      margin: '0 8px',
    },
  },
  vault_action_input: {
    backgroundColor:'#fff',
    boxShadow: 'none',
    border: 'none',
    outline: 0,
    textAlign: 'right',
    fontSize: 24,
    fontWeight: 600,
    color: '#3B3969',
    padding: "0.5rem 1rem 0.5rem 1rem",
  },
  vault_action_container_desktop: {
    backgroundColor: '#FD5298',
    borderRadius: 8,
    display: 'flex',
    gap:'15px',
    flexDirection:'column',
    alignItems: 'center',
  },
  vault_action_button_container_desktop: {
    display: 'none',
    [`@media screen and (min-width: 600px)`]: {
      display: 'block',
      flexShrink: 0,
      width: 200,
    },
  },
  vault_second_action_container: {
    padding: 16,
    backgroundColor: '#fff',
    borderRadius: 64,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 2,
  },
  vault_second_action_button: {
    borderRadius: 40,
    width: 188,
    height: 38,
    padding: '0 24px',
    cursor: 'pointer',
    transition: 'all .2s',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  vault_line_info_container: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#fff',
    height: 62,
    borderRadius: 62,
    padding: '0px 32px',
  },
  vault_instrument_logo_container: {
    display: 'none',
    [`@media screen and (min-width: 600px)`]: {
      width: 62,
      height: 62,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: '#fff',
      flexShrink: 0,
      borderRadius: '50%',
    },
  },
  vault_instrument_select: {
    width: '100%',
    '& .select__control::before': {
      content: "'INSTRUMENT'",
      paddingLeft: '8px',
      fontWeight: 700,
      color: '#16103A',
    },
    '& .select__control': {
      height: 62,
      border: 'none',
      borderRadius: 62,
      padding: '0 24px',
    },
    '& .select__single-value': {
      color: '#8E8DA0',
      fontWeight: 700,
      textAlign: 'right',
    },
    '& .select__indicator-separator': {
      display: 'none',
    },
  },
}
