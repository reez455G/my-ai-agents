---
name: meridian
description: Complete CLI command reference for the Meridian Solana DLMM liquidity-provider agent (balance, positions, deploy, close, screening, candidates, lessons, blacklist, config). Use when operating, querying, or automating the meridian trading bot from the command line.
---

# meridian — Solana DLMM LP Agent CLI

Data dir: ~/.meridian/

## Commands

### meridian balance
Returns wallet SOL and token balances.
```
Output: { wallet, sol, sol_usd, usdc, tokens: [{mint, symbol, balance, usd_value}], total_usd }
```

### meridian positions
Returns all open DLMM positions.
```
Output: { positions: [{position, pool, pair, in_range, age_minutes, ...}], total_positions }
```

### meridian pnl <position_address>
Returns PnL for a specific position.
```
Output: { pnl_pct, pnl_usd, unclaimed_fee_usd, all_time_fees_usd, current_value_usd, lower_bin, upper_bin, active_bin }
```

### meridian screen [--dry-run] [--silent]
Runs one AI screening cycle to find and deploy new positions.
```
Output: { done: true, report: "..." }
```

### meridian manage [--dry-run] [--silent]
Runs one AI management cycle over open positions.
```
Output: { done: true, report: "..." }
```

### meridian deploy --pool <addr> --amount <sol> [--bins-below 69] [--bins-above 0] [--strategy bid_ask|spot] [--dry-run]
Deploys a new LP position. All safety checks apply.
```
Output: { success, position, pool_name, txs, price_range, bin_step }
```

### meridian claim --position <addr>
Claims accumulated swap fees for a position.
```
Output: { success, position, txs, base_mint }
```

### meridian close --position <addr> [--skip-swap] [--dry-run]
Closes a position. Auto-swaps base token to SOL unless --skip-swap.
```
Output: { success, pnl_pct, pnl_usd, txs, base_mint }
```

### meridian swap --from <mint> --to <mint> --amount <n> [--dry-run]
Swaps tokens via Jupiter. Use "SOL" as mint shorthand.
```
Output: { success, tx, input_amount, output_amount }
```

### meridian candidates [--limit 5]
Returns top pool candidates fully enriched: pool metrics, token audit, holders, smart wallets, narrative, active bin, pool memory.
```
Output: { candidates: [{name, pool, bin_step, fee_pct, volume, tvl, organic_score, active_bin, smart_wallets, token: {holders, audit, global_fees_sol, ...}, holders, narrative, pool_memory}] }
```

### meridian study --pool <addr> [--limit 4]
Studies top LPers on a pool. Returns behaviour patterns, hold times, win rates, strategies.
```
Output: { pool, patterns: {top_lper_count, avg_hold_hours, avg_win_rate, ...}, lpers: [{owner, summary, positions}] }
```

### meridian token-info --query <mint_or_symbol>
Returns token audit, mcap, launchpad, price stats, fee data.
```
Output: { results: [{mint, symbol, mcap, launchpad, audit, stats_1h, global_fees_sol, ...}] }
```

### meridian token-holders --mint <addr> [--limit 20]
Returns holder distribution, bot %, top holder concentration.
```
Output: { mint, holders, top_10_real_holders_pct, bundlers_pct_in_top_100, global_fees_sol, ... }
```

### meridian token-narrative --mint <addr>
Returns AI-generated narrative about the token.
```
Output: { mint, narrative }
```

### meridian pool-detail --pool <addr> [--timeframe 5m]
Returns detailed pool metrics for a specific pool.
```
Output: { pool, name, bin_step, fee_pct, volume, tvl, volatility, ... }
```

### meridian search-pools --query <name_or_symbol> [--limit 10]
Searches pools by name or token symbol.
```
Output: { pools: [{pool, name, bin_step, fee_pct, tvl, volume, ...}] }
```

### meridian active-bin --pool <addr>
Returns the current active bin for a pool.
```
Output: { pool, binId, price }
```

### meridian wallet-positions --wallet <addr>
Returns DLMM positions for any wallet address.
```
Output: { wallet, positions: [...], total_positions }
```

### meridian config get
Returns the full runtime config.

### meridian config set <key> <value>
Updates a config key. Parses value as JSON when possible.
```
Valid keys: minTvl, maxTvl, minVolume, maxPositions, deployAmountSol, managementIntervalMin, screeningIntervalMin, managementModel, screeningModel, generalModel, autoSwapAfterClaim, minClaimAmount, outOfRangeWaitMinutes
```

### meridian lessons [--limit 50]
Lists all lessons from lessons.json. Shows rule, tags, pinned status, outcome, role.
```
Output: { total, lessons: [{id, rule, tags, outcome, pinned, role, created_at}] }
```

### meridian lessons add <text>
Adds a manual lesson with outcome=manual, role=null (applies to all roles).
```
Output: { saved: true, rule, outcome, role }
```

### meridian pool-memory --pool <addr>
Returns deploy history for a specific pool from pool-memory.json.
```
Output: { pool_address, known, name, total_deploys, win_rate, avg_pnl_pct, last_outcome, notes, history }
```

### meridian evolve
Runs evolveThresholds() over all closed position data and updates user-config.json.
```
Output: { evolved, changes, rationale }
```

### meridian blacklist add --mint <addr> --reason <text>
Permanently blacklists a token mint so it is never deployed into.
```
Output: { blacklisted, mint, reason }
```

### meridian blacklist list
Lists all blacklisted token mints with reasons and timestamps.
```
Output: { count, blacklist: [{mint, symbol, reason, added_at}] }
```

### meridian performance [--limit 200]
Shows all closed position performance history with summary stats.
```
Output: { summary: { total_positions_closed, total_pnl_usd, avg_pnl_pct, win_rate_pct, total_lessons }, count, positions: [...] }
```

### meridian discord-signals [clear]
Shows pending Discord signal queue from the discord-listener process.
```
Output: { count, pending, processed, signals: [{id, symbol, pool, author, channel, queued_at, rug_score, status}] }
```

### meridian start [--dry-run]
Starts the autonomous agent with cron jobs (management + screening).

## Flags
--dry-run     Skip all on-chain transactions
--silent      Suppress Telegram notifications for this run
