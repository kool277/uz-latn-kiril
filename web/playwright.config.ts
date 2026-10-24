import { defineConfig, devices } from '@playwright/test';

// End-to-end tests against the production build: `npm run build && npm run e2e`.
export default defineConfig({
  testDir: 'test/e2e',
  timeout: 60000,
  fullyParallel: true,
  retries: process.env['CI'] ? 1 : 0,
  reporter: process.env['CI'] ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: { baseURL: 'http://localhost:4300', trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: { command: 'node scripts/serve.mjs 4300', url: 'http://localhost:4300', reuseExistingServer: !process.env['CI'] }
});
