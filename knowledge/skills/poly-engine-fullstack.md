---
id: skill-poly-engine-fullstack
title: Poly Engine Fullstack Development
tags: [skill, poly-engine, fullstack, development]
source: /home/efsatu/.gemini/skills/poly-engine-fullstack/SKILL.md
imported_at: 2026-07-07
---

---
name: poly-engine-fullstack
description: Comprehensive management and troubleshooting guide for the Poly Engine Fullstack ecosystem, including the trading backend (Bun/TypeScript) and the Frontend UI (React/Node). Use this skill when deploying, modifying, or debugging the engine or its dashboard.
---

# Poly Engine Fullstack - Skill Guide

## 1. Architecture Overview

The system consists of two tightly coupled repositories:

### A. Trading Engine (`/opt/poly-engine-trade-late-down`)
- **Runtime:** Bun + TypeScript
- **Core Engine:** Handles market lifecycle, QuestDB telemetry, Chainlink Oracles, and Polymarket CLOB WebSockets.
- **Strategies:** Located in `engine/strategy/`. They load ML artifacts (JSON files in `research/`) to compute real-time probability `edge`.
- **State Management:** Uses `.json` and `.lock` files in `state/` to track PnL and enforce `sessionLoss` limits.
- **Execution:** Started individually via PM2 (e.g., `btc-probabilistic-edge-btc-5m`).

### B. UI Dashboard & Backend (`/opt/poly-engine-ui`)
- **Frontend:** React + Vite + TailwindCSS (served via `npm run preview` on port 4173/4174).
- **UI Backend:** Node.js Express server (`server/index.js`) running on port 4175.
- **Management:** The UI Backend programmatically manages the PM2 instances of the Trading Engine. It uses Redis (`poly_active_configs`) to maintain the single source of truth for active strategies.
- **Features:** Start/Stop strategies, Live Dashboard, Backtesting (QuestDB query-based), and Oracle Prediction analytics.

## 2. Operational Workflows

### 2.1 Restarting Strategies
**Rule:** ALWAYS restart trading strategies via the FE API. Do NOT use raw `pm2 restart` on the engine processes directly, as it will cause state desync with the UI Redis cache.
```bash
# Example: Stop and Start via FE API (Simulation Mode)
curl -X POST -H "Content-Type: application/json" -d '{"processId": "btc-probabilistic-edge-btc-5m"}' http://localhost:4175/api/stop
curl -X POST -H "Content-Type: application/json" -d '{"balance": 50, "maxLoss": 50, "maxProfit": 100, "tradeAmount": 1, "strategy": "probabilistic-edge-btc-5m", "tickers": ["btc"], "rounds": "0", "prod": false}' http://localhost:4175/api/start
```

### 2.2 Updating the UI
When `server/index.js` or React components in `src/` are modified:
1. Navigate to `/opt/poly-engine-ui`.
2. Build the frontend: `npm run build`
3. Restart the UI PM2 processes sequentially:
```bash
pm2 restart poly-engine-ui-backend
pm2 restart poly-engine-ui-preview
```

### 2.3 Handling PM2 Crashes
If PM2 crashes or returns an empty list, but Node/Bun processes are still running:
1. Kill zombie processes to free up ports: `kill -9 <PID>`
2. Start the UI explicitly:
   - `pm2 start server/index.js --name poly-engine-ui-backend`
   - `pm2 start "npm run preview -- --host" --name poly-engine-ui-preview`
3. Use the FE API to spawn the trading engine processes.
4. Save state: `pm2 save`

## 3. Common Pitfalls
- **ENOSPC on Lock Files:** The Bun engine will fail to start if the previous session hit the `maxLoss` limit. The logs might misleadingly show `ENOSPC`. Check the `.json` file in `state/` and look at `sessionLoss`. If it exceeds `maxLoss`, the bot shuts down intentionally.
- **Max Loss Signage:** The FE API `maxLoss` parameter expects a POSITIVE number (e.g., `50` means $50 max loss). Passing `-50` will cause immediate shutdown logic evaluation (`if (0 <= -(-50))`).
- **Git Conflicts:** Always check for `server/index.js` conflicts before pulling in `poly-engine-ui`, as both remote and local agents frequently modify it.
