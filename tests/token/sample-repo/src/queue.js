'use strict';

// Sends jobs (usually label print jobs) through a sender function and retries
// failures with exponential backoff. Jobs run one at a time in FIFO order.
class RetryQueue {
  constructor(sender, { maxRetries = 3, baseDelayMs = 200, sleep } = {}) {
    this.sender = sender;
    this.maxRetries = maxRetries;
    this.baseDelayMs = baseDelayMs;
    this.sleep = sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.jobs = [];
    this.deadLetter = [];
  }

  enqueue(job) {
    this.jobs.push(job);
  }

  async drain() {
    const sent = [];
    while (this.jobs.length > 0) {
      const job = this.jobs.shift();
      let attempt = 0;
      for (;;) {
        try {
          await this.sender(job);
          sent.push(job);
          break;
        } catch (err) {
          attempt++;
          if (attempt > this.maxRetries) {
            this.deadLetter.push({ job, error: err.message });
            break;
          }
          await this.sleep(this.baseDelayMs * 2 ** (attempt - 1));
        }
      }
    }
    return { sent: sent.length, failed: this.deadLetter.length };
  }
}

module.exports = { RetryQueue };
