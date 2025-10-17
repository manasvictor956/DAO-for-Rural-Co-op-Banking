import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "clarinet", // Use the clarinet environment
    singleThread: true,
    testTimeout: 60000,
    coverage: {
      provider: "c8",
      reporter: ["text", "html", "lcov"],
    },
  },
});