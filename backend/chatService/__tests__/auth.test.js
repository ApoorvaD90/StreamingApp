process.env.JWT_SECRET = 'test-secret';
const jwt = require('jsonwebtoken');
const { verifyToken, buildUserContext } = require('../util/auth');

test('verifies a valid token', () => {
  const token = jwt.sign({ sub: 'u1', email: 'jane@x.com' }, process.env.JWT_SECRET);
  expect(verifyToken(token).sub).toBe('u1');
});

test('returns null for a bad or missing token', () => {
  jest.spyOn(console, 'error').mockImplementation(() => {});
  expect(verifyToken('garbage')).toBeNull();
  expect(verifyToken(undefined)).toBeNull();
});

test('builds user context with sensible defaults', () => {
  expect(buildUserContext({ sub: 'u1', email: 'jane@x.com' }))
    .toEqual({ id: 'u1', email: 'jane@x.com', role: 'user', name: 'jane' });
});
