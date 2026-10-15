import {
  AUTH_API_URL,
  STREAMING_API_URL,
  ADMIN_API_URL,
  CHAT_API_URL,
  CHAT_SOCKET_URL,
} from './config/env';

test('all API endpoints are configured', () => {
  [AUTH_API_URL, STREAMING_API_URL, ADMIN_API_URL, CHAT_API_URL, CHAT_SOCKET_URL].forEach((url) => {
    expect(typeof url).toBe('string');
    expect(url.length).toBeGreaterThan(0);
  });
});
