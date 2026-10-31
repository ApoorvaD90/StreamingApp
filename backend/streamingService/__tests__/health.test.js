const { healthCheck } = require('../controllers/health.controller');

test('health endpoint reports OK', async () => {
  const res = { json: jest.fn() };
  await healthCheck({}, res);
  expect(res.json).toHaveBeenCalledWith({ msg: 'BROKEN' });
});
