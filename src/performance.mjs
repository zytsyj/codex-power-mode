export function percentile(values, fraction) {
  const sorted = values.filter(Number.isFinite).toSorted((left, right) => left - right);
  if (sorted.length === 0) return 0;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * fraction) - 1));
  return sorted[index];
}

export function summarizeProcessSamples(samples) {
  const cpu = samples.map((sample) => sample.cpuPercent).filter(Number.isFinite);
  const rss = samples.map((sample) => sample.rssBytes).filter(Number.isFinite);
  const mean = (values) => values.length === 0 ? 0 : values.reduce((total, value) => total + value, 0) / values.length;
  return {
    samples: Math.min(cpu.length, rss.length),
    cpuPercent: {
      mean: Number(mean(cpu).toFixed(2)),
      p95: Number(percentile(cpu, 0.95).toFixed(2)),
      max: Number(Math.max(0, ...cpu).toFixed(2))
    },
    rssMB: {
      mean: Number((mean(rss) / 1_048_576).toFixed(2)),
      max: Number((Math.max(0, ...rss) / 1_048_576).toFixed(2))
    }
  };
}

export function performanceBudgetChecks(scenarios, budgets) {
  const checks = [];
  for (const [scenario, roles] of Object.entries(scenarios)) {
    for (const [role, summary] of Object.entries(roles)) {
      const limit = scenario === "idle" ? budgets.idleCpuP95?.[role] : budgets.activeCpuP95?.[role];
      if (Number.isFinite(limit)) {
        checks.push({
          metric: `${scenario}.${role}.cpuP95`,
          value: summary.cpuPercent.p95,
          limit,
          pass: summary.cpuPercent.p95 <= limit
        });
      }
      const memoryLimit = budgets.maxRssMB?.[role];
      if (Number.isFinite(memoryLimit)) {
        checks.push({
          metric: `${scenario}.${role}.rssMaxMB`,
          value: summary.rssMB.max,
          limit: memoryLimit,
          pass: summary.rssMB.max <= memoryLimit
        });
      }
      const powerLimit = scenario === "idle" ? budgets.idlePowerScore?.[role] : budgets.activePowerScore?.[role];
      if (Number.isFinite(powerLimit) && Number.isFinite(summary.energyImpact?.powerScore)) {
        checks.push({
          metric: `${scenario}.${role}.powerScore`,
          value: summary.energyImpact.powerScore,
          limit: powerLimit,
          pass: summary.energyImpact.powerScore <= powerLimit
        });
      }
      const threadLimit = budgets.maxThreads?.[role];
      if (Number.isFinite(threadLimit) && Number.isFinite(summary.energyImpact?.threads)) {
        checks.push({
          metric: `${scenario}.${role}.threads`,
          value: summary.energyImpact.threads,
          limit: threadLimit,
          pass: summary.energyImpact.threads <= threadLimit
        });
      }
    }
  }
  return checks;
}
