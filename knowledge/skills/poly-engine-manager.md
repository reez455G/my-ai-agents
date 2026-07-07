---
id: skill-poly-engine-manager
title: Poly Engine Manager Operations
tags: [skill, poly-engine, manager, operations, pm2]
source: ~/.gemini/skills/poly-engine-manager/SKILL.md
imported_at: 2026-07-07
---

---
name: poly-engine-manager
description: Manage and operate the Poly Engine trading application (including its web UI, backend controller, Redis, PM2, and individual strategies). Use this skill when you need to troubleshoot, rebuild, restore, or monitor the trading engine and UI components.
---

# Poly Engine Manager: Operation and Maintenance Guide

This skill provides unified workflows, scripts, and commands to manage the Poly Engine trading system and its companion Web UI.

## Components Architecture

*   **Trading Engine**: Located at `/opt/poly-engine-trade-late-down`. Runs TypeScript strategy files using Bun. Managed via PM2.
*   **Web UI Frontend**: Located at `/opt/poly-engine-ui`. Built with Vite and React. Served as a production build via `vite preview` managed by PM2 as `poly-engine-ui-preview`.
*   **Web UI Backend**: Located at `/opt/poly-engine-ui/server`. Built with Node.js/Express. Listens on port `4175`. Managed by PM2 as `poly-engine-ui-backend`.
*   **Redis**: Key-value store used to persist active configurations (`poly_active_configs`) and session history (`poly_sessions`).

---

## 1. Quick Diagnostics

To check the overall system health, run:
```bash
# Check PM2 processes (both trading strategies and UI services)
pm2 list

# Check listening ports (4174=UI, 4175=Backend, 6379=Redis)
ss -ltnp | grep -E '4174|4175|6379'

# Check active backend configurations in Redis
redis-cli get poly_active_configs
```

---

## 2. Managing the UI Server & Preview

### How to Rebuild and Restart UI
If you modify files inside the UI (`/opt/poly-engine-ui/src/` or `vite.config.ts`), you must rebuild and restart the UI services.

We manage the UI backend and preview services under PM2 to protect them from terminal sandbox cleanups. To rebuild and restart them:
```bash
# Execute the UI management script
/home/efsatu/.gemini/skills/poly-engine-manager/scripts/manage-ui.sh
```

### Checking UI Logs in PM2
```bash
# View UI Backend logs
pm2 logs poly-engine-ui-backend --lines 100

# View Vite Preview logs
pm2 logs poly-engine-ui-preview --lines 100
```

---

## 3. Restoring Running Strategies

If the server restarts, PM2 processes and `poly_active_configs` in Redis may get cleared. You can restore them to their last known configurations using the helper script:

```bash
# Execute the restore script
python3 /home/efsatu/.gemini/skills/poly-engine-manager/scripts/restore-strategies.py
```

---

## 4. Registering a New Asset Ticker & Strategy

To add support for a new token (e.g. `bnb`):

1.  **Backend registration**: Edit [server/index.js](file:///opt/poly-engine-ui/server/index.js) and add the ticker meta to `ASSET_TICKER_META`:
    ```javascript
    bnb: { label: 'BNB', binanceSymbol: 'BNBUSDT', coinbaseProduct: 'BNB-USD' }
    ```
2.  **Frontend registration**: Edit [src/pages/Dashboard.tsx](file:///opt/poly-engine-ui/src/pages/Dashboard.tsx) and add:
    *   The strategy name to `AVAILABLE_STRATEGIES`
    *   The ticker name to `AVAILABLE_TICKERS`
3.  **Rebuild and Restart**: Run `/home/efsatu/.gemini/skills/poly-engine-manager/scripts/manage-ui.sh` to apply the changes.
