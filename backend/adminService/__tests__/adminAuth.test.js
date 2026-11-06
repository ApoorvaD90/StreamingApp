process.env.JWT_SECRET = 'test-secret';
const jwt = require('jsonwebtoken');
const { adminAuth } = require('../middleware/adminAuth');

const mockRes = () => {
  const res = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
};
const reqWith = (token) => ({ headers: token ? { authorization: `Bearer ${token}` } : {} });

test('rejects request without token (401)', () => {
  const res = mockRes();
  const next = jest.fn();
  adminAuth(reqWith(), res, next);
  expect(res.status).toHaveBeenCalledWith(401);
  expect(next).not.toHaveBeenCalled();
});

test('rejects non-admin user (403)', () => {
  const res = mockRes();
  const token = jwt.sign({ sub: 'u1', role: 'user' }, process.env.JWT_SECRET);
  adminAuth(reqWith(token), res, jest.fn());
  expect(res.status).toHaveBeenCalledWith(403);
});

test('rejects tampered token (401)', () => {
  jest.spyOn(console, 'error').mockImplementation(() => {});
  const res = mockRes();
  const token = jwt.sign({ sub: 'u1', role: 'admin' }, 'wrong-secret');
  adminAuth(reqWith(token), res, jest.fn());
  expect(res.status).toHaveBeenCalledWith(401);
});

test('allows admin user through', () => {
  const next = jest.fn();
  const req = reqWith(jwt.sign({ sub: 'u1', email: 'a@b.com', role: 'admin' }, process.env.JWT_SECRET));
  adminAuth(req, mockRes(), next);
  expect(next).toHaveBeenCalled();
  expect(req.user).toEqual({ _id: 'u1', email: 'a@b.com', role: 'admin' });
});
