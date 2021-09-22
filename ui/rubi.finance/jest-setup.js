const propTypes = jest.genMockFromModule('prop-types');
propTypes.oneOfType = () => ({});
propTypes.arrayOf = () => ({});
propTypes.shape = () => ({ isRequired: {} });
propTypes.oneOf = () => ({ isRequired: {} });
propTypes.instanceOf = () => ({ isRequired: {} });
propTypes.func = { isRequired: {} };
propTypes.node = {};
propTypes.object = {};
propTypes.array = {};
propTypes.string = {};
propTypes.number = {};
jest.mock('prop-types', () => propTypes);
jest.mock('prop-types/checkPropTypes', () => () => true);

window.moment = require('moment');
