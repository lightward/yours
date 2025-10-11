import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'happy-dom',
    setupFiles: ['./test/setup.js'],
    globals: true,
    testTimeout: 10000, // 10 seconds for async integration tests
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      exclude: [
        'node_modules/**',
        'test/**',
        '**/*.config.js'
      ]
    }
  }
})
