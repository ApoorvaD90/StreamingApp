const express = require('express');
const { metricsMiddleware, metricsHandler } = require('../util/metrics');

let server;
let baseUrl;

beforeAll((done) => {
  const app = express();
  app.use(metricsMiddleware);
  app.get('/metrics', metricsHandler);
  app.get('/api/items/:id', (req, res) => res.json({ id: req.params.id }));
  server = app.listen(0, () => {
    baseUrl = `http://127.0.0.1:${server.address().port}`;
    done();
  });
});

afterAll((done) => {
  server.close(done);
});

test('/metrics exposes Node.js process metrics in Prometheus format', async () => {
  const res = await fetch(`${baseUrl}/metrics`);
  expect(res.status).toBe(200);
  expect(res.headers.get('content-type')).toMatch(/text\/plain/);
  expect(await res.text()).toContain('process_cpu_user_seconds_total');
});

test('requests are counted per route template, not per raw URL', async () => {
  await fetch(`${baseUrl}/api/items/42`);
  await fetch(`${baseUrl}/api/items/43`);
  const body = await (await fetch(`${baseUrl}/metrics`)).text();
  expect(body).toMatch(/http_request_duration_seconds_count\{method="GET",route="\/api\/items\/:id",status_code="200"\} 2/);
  expect(body).not.toContain('/api/items/42');
});
