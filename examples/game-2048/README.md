# 2048 — backend-authoritative game on vxui

A full 2048 implementation where **every rule lives in V**: sliding, merging,
tile spawning, win/lose detection, scoring. The page contains zero game logic
— it renders HTML fragments and forwards arrow keys.

## What it demonstrates

| vxui capability | How |
|---|---|
| Backend-authoritative state | `App.board` is the only game state in existence; the browser holds nothing |
| One WS round-trip per input | Each arrow key fires one `/move` rpc — measured at **0.6ms p50 / 1.3ms p99** loopback (`perf_rtt_test.v`) |
| Declarative keyboard triggers | Four hidden divs with `hx-trigger="keyup from:body [key=='ArrowLeft']"` — no custom JS anywhere |
| Multi-target partial updates | One response swaps `#board` (main target) and patches `#hud` (`hx-swap-oob`) |

## Run

```bash
v run examples/game-2048/main.v
```

Click into the window and use the arrow keys. "New Game" resets.

## Notes

- Fast key-mashing is safe: same-connection messages are strictly ordered,
  and each move costs ~0.6ms of round-trip.
- The sandbox statement-count limit (≤10 semicolons) applies to injected
  scripts, not to this pattern: the server returns plain fragments.
