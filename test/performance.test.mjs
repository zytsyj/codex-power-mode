import assert from "node:assert/strict";
import test from "node:test";
import { performanceBudgetChecks, percentile, summarizeProcessSamples } from "../src/performance.mjs";

test("performance summaries use deterministic means, percentiles, and byte conversion", () => {
  assert.equal(percentile([10, 2, 8, 4], 0.5), 4);
  assert.deepEqual(summarizeProcessSamples([
    { cpuPercent: 1, rssBytes: 10 * 1_048_576 },
    { cpuPercent: 3, rssBytes: 14 * 1_048_576 }
  ]), {
    samples: 2,
    cpuPercent: { mean: 2, p95: 3, max: 3 },
    rssMB: { mean: 12, max: 14 }
  });
});

test("performance budgets distinguish idle and active CPU while bounding memory", () => {
  const summary = { cpuPercent: { p95: 4 }, rssMB: { max: 60 } };
  const checks = performanceBudgetChecks({ idle: { hud: summary }, burst: { hud: summary } }, {
    idleCpuP95: { hud: 3 },
    activeCpuP95: { hud: 40 },
    maxRssMB: { hud: 100 }
  });
  assert.deepEqual(checks.map(({ metric, pass }) => ({ metric, pass })), [
    { metric: "idle.hud.cpuP95", pass: false },
    { metric: "idle.hud.rssMaxMB", pass: true },
    { metric: "burst.hud.cpuP95", pass: true },
    { metric: "burst.hud.rssMaxMB", pass: true }
  ]);
});
