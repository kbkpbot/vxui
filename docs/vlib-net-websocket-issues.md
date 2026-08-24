# vlib/net/websocket — Issues Found During vxui Development

**Environment:** V 0.5.2 (commit 9142d68), Linux x86_64, loopback TCP,
headless Chrome as WS client.
**Context:** while building a binary upload channel for the vxui desktop
framework we measured multi-megabyte WebSocket transfers and traced the results
back to the issues below. Measured on an idle machine; numbers are reproducible.

---

## Issue 1 (performance): `read_payload()` reads one byte per syscall

**Location:** `vlib/net/websocket/message.v`, `fn (mut ws Client) read_payload`

```v
mut buffer := []u8{cap: frame.payload_len}
mut read_buf := [1]u8{}
mut bytes_read := 0
for bytes_read < frame.payload_len {
    len := ws.socket_read_ptr(&read_buf[0], 1)!   // ONE byte per call
    if len != 1 {
        return error('expected read all message, got zero')
    }
    bytes_read += len
    buffer << read_buf[0]
}
```

Every payload byte costs one `lock{}` (see `socket_read_ptr` in `io.v`) plus one
1-byte TCP `read()` syscall (~6 µs each on Linux). This caps throughput at
roughly **150 KB/s regardless of frame size or count** — only total bytes
matter.

### Measurements (10 MB transferred over loopback, server-side receive)

| Framing                        | Wall time to receive |
|--------------------------------|---------------------:|
| 7 frames × 1.5 MB              |              69.40 s |
| 40 frames × 256 KB             |              69.41 s |

The constant time across framings is the fingerprint of a per-byte cost, not a
per-frame or bandwidth limit.

Corroborating data point from an earlier JSON-chunked uploader built on the
same library: each 1.5 MB chunk took ~9.6 s end-to-end (≈2 MB of base64 text ×
per-byte reads ≈ 7 s, plus JSON parse).

### Impact

Every large WebSocket message received by any client or server built on this
module is affected — multi-megabyte frames are ordinary WebSocket usage
(binary transfers, file sync, log streaming).

### Suggested fix

```v
mut buffer := []u8{len: frame.payload_len}      // preallocate, fixed length
mut bytes_read := 0
for bytes_read < frame.payload_len {
    n := ws.socket_read_ptr(&buffer[bytes_read], frame.payload_len - bytes_read)!
    if n <= 0 {
        return error('expected read all message, got zero')
    }
    bytes_read += n
}
```

The masking XOR afterwards stays unchanged. Note: a first attempt at this patch
did not compile as-is (`&buffer[bytes_read]` needs the index-bounds treatment V
expects there) and was not pursued past that point — the approach above is
validated by measurement of the current cost structure, but the patch itself
still needs to be finished against `v test vlib/net/websocket/`.

---

## Issue 2 (correctness): server watchdog kills busy connections

**Location:** `vlib/net/websocket/websocket_server.v`, `fn (mut s Server) handle_ping`, ~line 112

```v
if (time.now().unix() - c.client.last_pong_ut) > s.get_ping_interval() * 2 {
    clients_to_remove << c.client.id
    c.client.close(1000, 'no pong received') or { continue }
}
```

`last_pong_ut` is updated only when the connection's read loop *processes* a
pong frame. While that loop is busy receiving a large message (or a handler is
running), inbound pongs sit in the kernel buffer unprocessed — so a maximally
active connection looks exactly like a dead one. The metric measures "pong
processing latency", not "connection liveness".

Observed effect: transferring a file over a vxui WebSocket caused the server to
close the very connection doing the transfer ("no pong received"), tearing down
the whole session.

### Suggested fix (activity-aware staleness)

Refresh the liveness timestamp whenever *any* frame is processed in
`Client.listen()` (data frames included), not only pongs:

```v
// in listen(), after read_next_message() returns:
ws.last_rx_ut = time.now().unix()
```

and change the watchdog condition to:

```v
last_seen := max(ws.last_pong_ut, ws.last_rx_ut)
if time.now().unix() - last_seen > s.get_ping_interval() * 2 { ... }
```

Pings stay useful for probing *idle* connections; actively-transferring
connections become self-evidently alive, with no application-level pause/resume
state that could leak.

---

## Issue 3 (minor performance): `parse_frame_header()` also reads bytewise

**Location:** `vlib/net/websocket/message.v`, bottom of the function.

Frame headers (2–14 bytes) are read one `socket_read_ptr(..., 1)` call at a
time — ~10 syscalls + lock acquisitions per frame. Negligible next to Issue 1
for large payloads, but it taxes high-frequency small-message workloads. Same
remedy shape as Issue 1 (bulk-read into a small stack buffer, then parse).

---

## Issue 4 (API): `new_server()` ignores its `route` parameter

**Location:** `vlib/net/websocket/websocket_server.v`, line 51.

```v
pub fn new_server(family net.AddrFamily, port int, route string, opt ServerOpt) &Server {
    return &Server{
        ls:     unsafe { nil }
        family: family
        port:   port
        logger: opt.logger
    } // `route` is silently dropped — Server has no field for it
}
```

The signature suggests resource-based routing, but the value is never stored or
compared. Meanwhile the handshake *does* parse the real request path
(`handshake.v`: `resource_name: get_tokens[1]`), so single-port multiplexing by
path would be feasible — today callers must inspect `resource_name` themselves
or run multiple listeners. At minimum the parameter should be documented as
unused (or removed); better, either store/expose it or implement path matching.

---

## Observation (not filed as bug): unbounded write retry on timeout

**Location:** `vlib/net/websocket/io.v`, `socket_write`, non-TLS branch.

```v
for {
    n := ws.conn.write(bytes) or {
        if err.code() == net.err_timed_out_code {
            continue            // unconditional retry
        }
        return err
    }
    return n
}
```

A permanently stalled peer turns a timed-out write into an infinite retry loop.
Consider a retry budget or propagating the error after N attempts.

---

## Reproduction sketch (Issue 1)

Any echo-style server/client pair from `websocket_test.v`, scaled up:

1. Server echoes whatever it receives; client sends a single binary frame with
   a multi-megabyte payload (e.g. 10 MB).
2. Time the server-side `on_message` arrival vs. send start.
3. Expected with current code: ~70 s for 10 MB on loopback (~150 KB/s).
4. With the bulk-read fix: loopback should complete in well under a second.

Independent confirmation without any patch: keep the total payload constant and
vary the framing (1 big frame vs. many small ones). Per-byte-cost predicts —
and we measured — identical wall times.

---

*Filed from vxui development (https://github.com/kbkpbot/vxui). Happy to turn
Issues 1–3 into upstream PRs once the reference fix compiles clean against the
full websocket test suite.*
