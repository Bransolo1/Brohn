import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 60000,
  expect: { timeout: 15000 },
  fullyParallel: false,
  workers: 1,
  reporter: [['list'], ['json', { outputFile: 'test-results/browser-results.json' }]],
  use: { baseURL: 'http://127.0.0.1:3849', trace: 'retain-on-failure', screenshot: 'only-on-failure',
    channel: process.env.PLAYWRIGHT_CHANNEL || undefined },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'narrow', use: { ...devices['Desktop Chrome'], viewport: { width: 390, height: 844 } } }
  ],
  webServer: {
    command: 'node scripts/start-browser-test-server.mjs',
    url: 'http://127.0.0.1:3849',
    reuseExistingServer: false,
    timeout: 30000
  }
});
