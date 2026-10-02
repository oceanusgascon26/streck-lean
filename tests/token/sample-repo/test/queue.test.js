'use strict';
const assert = require('assert');
const { RetryQueue } = require('../src/queue');

test('queue retries then dead-letters', async () => {
  let calls = 0;
  const q = new RetryQueue(async () => { calls++; throw new Error('ECONNREFUSED'); },
    { maxRetries: 2, sleep: async () => {} });
  q.enqueue({ id: 1 });
  const r = await q.drain();
  assert.strictEqual(calls, 3);
  assert.deepStrictEqual(r, { sent: 0, failed: 1 });
});
