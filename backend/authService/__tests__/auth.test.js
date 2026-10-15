process.env.JWT_SECRET = 'test-secret';
const { healthCheck } = require('../controllers/healthCheck.controller');
const { jwtTokenGenerator, jwtTokenVerify } = require('../util/jwtAuth');

test('health endpoint reports OK', async () => {
  const res = { send: jest.fn() };
  await healthCheck({}, res);
  expect(res.send).toHaveBeenCalledWith({ status: 'OK' });
});

test('generated JWT verifies and carries the user claims', () => {
  const token = jwtTokenGenerator({ _id: 'u1', email: 'a@b.com', name: 'A', role: 'admin' });
  const decoded = jwtTokenVerify(token);
  expect(decoded.sub).toBe('u1');
  expect(decoded.email).toBe('a@b.com');
  expect(decoded.role).toBe('admin');
});

test('invalid or missing JWT returns null', () => {
  jest.spyOn(console, 'error').mockImplementation(() => {});
  expect(jwtTokenVerify('not-a-token')).toBeNull();
  expect(jwtTokenVerify(undefined)).toBeNull();
});
