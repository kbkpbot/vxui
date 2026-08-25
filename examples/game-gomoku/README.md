# Gomoku — two-window real-time play on vxui

A full five-in-a-row implementation where **all rules live in V** and TWO
browser windows play against each other on the same backend session: the
first window seats as BLACK, the second as WHITE, further windows spectate.

## What it demonstrates

| vxui capability | How |
|---|---|
| **Multi-window real-time play** | Two windows, one backend session — moves are broadcast to every window via `oob_update`, so both boards stay in sync with no polling |
| **Caller identity** | `dispatch_rpc` injects `message.client_id`; `/place` validates the caller's color, turn order, and cell occupancy before accepting a stone |
| **Targeted rejection feedback** | Invalid moves (wrong turn, occupied cell, spectator) are reported only to the offending window via `send_to_client` |
| **Per-client JS injection** | Each window learns its color through `post_js_client` (fire-and-forget, safe inside handlers) |
| **225 declarative triggers** | Every empty cell is its own `hx-post` with fixed coordinates — no custom game JS on the page |
| **Reconnect-friendly** | `/state` returns the CURRENT match without resetting; a rejoined window pulls the live board |

## Run

```bash
v run examples/game-gomoku/main.v
```

A window opens as BLACK. Open the same page in a second window — it seats as
WHITE. Click intersections to place stones.

## Implementation notes

- Seats are assigned at `/state` (fetched on every window load) and lazily at
  `/place` (atomic with the move, covering the load race).
- The response body of `/place` is empty: propagation happens through
  `broadcast_state()`, which reaches the caller too.
- Rule helpers return `void` and report rejections via a field —
  string-returning helpers with custom parameters trip fire_call's comptime
  dispatch (see AGENTS.md).
