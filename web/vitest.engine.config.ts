import { defineConfig } from 'vitest/config';

// Engine tests run in Node (no browser): `npm run test:engine`. Angular component tests use `ng test`.
export default defineConfig({
  test: {
    include: ['test/engine/**/*.test.ts'],
    environment: 'node',
    testTimeout: 120000
  }
});
