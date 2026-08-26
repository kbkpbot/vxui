# V3 false positive: "cannot use ... expected <fn-type alias>" for inline fn literal in a generic function

> Minimal reproduction, root-cause analysis, and stable-vs-V3 comparison. This bug was
> discovered while building `vxui` (a V UI framework) whose `startup_ws_server[T]`
> function passes inline `fn` literals to `net.websocket` callbacks from inside a
> generic function — exactly the shape that triggers the false positive.

## Environment

- **V version:** `V 0.5.2 1509dde` (git `1509ddefc net.websocket: batch payload read (#28174)`)
- **OS:** Linux 6.8.0-138-generic x86_64 (Ubuntu)
- **Backend:** V3 experimental frontend (auto-enabled; falls back to the stable frontend on failure)

## Summary

When an inline `fn` literal that is **structurally identical** to a vlib fn-type
alias is passed to a vlib function/method that takes that alias as a parameter,
**and the call site is inside a generic function**, the V3 frontend rejects the
program with a spurious type error:

```
cannot use `fn (&jsonrpc.Request, &jsonrpc.ResponseWriter)` as argument 2 to `r.register`; expected `jsonrpc.Handler`
```

The **stable** frontend accepts the very same code and produces a working binary.
The program runs correctly. So this is a V3 type-checker false positive, not a
real type mismatch.

## Minimal reproduction (stable vlib module: `net.jsonrpc`)

No `x.*` and no `net.websocket` — `net.jsonrpc` is a stable vlib module.

File `main.v`:

```v
module main

import net.jsonrpc

// An inline fn literal is passed to a vlib method that takes a fn-type alias
// (`jsonrpc.Handler = fn (req &Request, mut wr ResponseWriter)`), from INSIDE
// a generic function.
fn startup[T]() {
    mut r := jsonrpc.Router{}
    r.register('x', fn (req &jsonrpc.Request, mut wr jsonrpc.ResponseWriter) {
    })
}

struct App {}

fn main() {
    startup[App]()
}
```

Compile (forcing V3 to finish instead of OOM-falling-back early):

```bash
v -o bin main.v -no-memory-limit
```

### Observed (V3 frontend)

```
main.v:11:7: error: cannot use `fn (&jsonrpc.Request, &jsonrpc.ResponseWriter)` as argument 2 to `r.register`; expected `jsonrpc.Handler`
note: V3 could not build this program, so V used the stable compiler instead.
```

The reported literal type `fn (&jsonrpc.Request, &jsonrpc.ResponseWriter)` is exactly
the expansion of `jsonrpc.Handler = fn (req &Request, mut wr ResponseWriter)` —
`mut wr jsonrpc.ResponseWriter` desugars to a `&jsonrpc.ResponseWriter` parameter.
The two types are identical, so the error is false.

### Expected (stable frontend)

The program should compile and run. It does:

```bash
$ v -o bin main.v -no-memory-limit
# (V3 fails, falls back to stable)
$ ./bin && echo RUNS_OK
RUNS_OK
```

A binary is produced and executes successfully, proving the types are compatible.

## Second reproduction (the real `vxui` / `net.websocket` case)

This is the exact shape `vxui` uses — all three callbacks set from inside a
generic function. File `main.v`:

```v
module main

import net.websocket

fn startup_ws_server[T]() ! {
    mut s := websocket.new_server(.ip, 1234, '')
    s.on_connect(fn (mut con websocket.ServerClient) !bool {
        return true
    })!
    s.on_message_ref(fn (mut c websocket.Client, msg &websocket.Message, v voidptr) ! {
        return
    }, unsafe { nil })
    s.on_close_ref(fn (mut c websocket.Client, code int, reason string, v voidptr) ! {
        return
    }, unsafe { nil })
}

struct App {}

fn main() {
    startup_ws_server[App]()!
}
```

V3 emits the same class of false positive for **all three** callbacks — exactly
what `vxui` shows:

```
cannot use `fn (&websocket.ServerClient) !bool` as argument 1 to `s.on_connect`; expected `websocket.AcceptClientFn`
cannot use `fn (&websocket.Client, &websocket.Message, voidptr) !` as argument 1 to `s.on_message_ref`; expected `websocket.SocketMessageFn2`
cannot use `fn (&websocket.Client, int, string, voidptr) !` as argument 1 to `s.on_close_ref`; expected `websocket.SocketCloseFn2`
```

Stable compiles and runs it. This is the real-world trigger found while building
`vxui`.

## Why this is a V3 false positive (not a user error)

- The literal's inferred type `fn (&jsonrpc.Request, &jsonrpc.ResponseWriter)` is the
  canonical expansion of the alias `jsonrpc.Handler = fn (req &Request, mut wr ResponseWriter)`.
  There is no actual mismatch.
- The **stable** compiler accepts the identical source and the resulting binary
  runs correctly, so the types are genuinely compatible.
- The error **only** appears when the call site is inside a generic function
  (`fn startup[T]()`). Removing the generic parameter (making it a plain
  `fn startup()`) makes V3 accept the code — even though the fn literal and the
  alias are unchanged. This points at a V3 generic-instantiation / alias-expansion
  interaction, not at the fn types themselves.

### Narrowing evidence

| Repro | Inside generic fn? | V3 result |
|-------|--------------------|-----------|
| inline literal, plain `fn main`/free call | no | accepts |
| inline literal, call in `fn startup[T]()` | **yes** | rejects (false positive) |
| vlib alias used as a *parameter* (no inline literal) | n/a | accepts |

The trigger is specifically: **inline fn literal + vlib fn-type alias parameter + generic function context**.

## Workaround

No code change is required. V automatically falls back to the stable frontend when
V3 fails, and the program builds and runs correctly:

```
note: V3 could not build this program, so V used the stable compiler instead.
```

So the three "cannot use" errors seen in `vxui` are noise from the V3 frontend;
they do not affect the working binary.

## Suggested fix area (for V maintainers)

The V3 type checker appears to compare the inline literal's type against the
fn-type alias **without expanding the alias** (or expands it incorrectly) in the
generic-instantiation path, producing a spurious mismatch. The stable frontend's
unification should be the reference behavior. Likely place to look: V3's handling
of `type X = fn (...)` aliases when the call site is generic.

## Can this be reproduced without importing any library?

**No.** This bug is intrinsically about fn-type aliases defined in a
**separately-compiled (vlib) module**. A locally-defined alias never triggers it,
even inside a generic function:

```v
module main

type Handler = fn (mut c Con) !bool   // defined in the SAME module, no imports
struct Con {}
fn register(h Handler) {}
fn startup[T]() {
    register(fn (mut c Con) !bool { return true })
}
struct App {}
fn main() { startup[App]() }
```

This compiles cleanly under V3 (binary produced, no error). Verified:

| Repro | Alias defined in | V3 result |
|-------|------------------|-----------|
| inline literal, same-module alias, plain fn | current module | accepts |
| inline literal, same-module alias, generic fn | current module | **accepts** |
| inline literal, local submodule `m` alias, generic fn | `m` (compiled in same unit) | accepts |
| inline literal, `~/.vmodules/m` alias, generic fn | installed module | accepts |
| inline literal, `net.jsonrpc.Handler`, generic fn | **vlib (precompiled, stable)** | **rejects (false positive)** |
| inline literal, `x.async.JobFn`, generic fn | **vlib (precompiled, `x/` experimental)** | **rejects (false positive)** |
| inline literal, `net.websocket.AcceptClientFn`, generic fn | **vlib (precompiled)** | **rejects (false positive)** |

The only way to trigger the false positive is to use a vlib fn-type alias. So a
reproduction without *any* import cannot exist — the bug is precisely V3's failure
to expand/unify a **precompiled, cross-module** fn-type alias. The smallest
possible repro therefore imports exactly one vlib module that exports such an
alias. Two good choices:

- `net.jsonrpc` (`Handler = fn (req &Request, mut wr ResponseWriter)`) — **stable** vlib module, prefer this for the bug report.
- `net.websocket` (`AcceptClientFn` / `SocketMessageFn2` / `SocketCloseFn2`) — the real-world case `vxui` hits.
- `x.async` (`JobFn = fn (mut context.Context) !`) — also works, but `x/` modules are experimental, so avoid for the report.

### Why `builtin` (auto-imported) is not enough

We checked `builtin` specifically, since it needs no `import` statement. It exposes
only these fn-type aliases, **none** of which have a `mut` V-struct/interface
binding parameter:

- `FnExitCb = fn ()` — no parameters
- `FnGC_WarnCB = fn (const_msg &char, arg usize)` — C `&char` reference, not a `mut` V binding
- `FnSortCB = fn (const_a voidptr, const_b voidptr) int` — `voidptr`, not `mut`

The V3 false positive only fires when the alias parameter is written as a **`mut`
V-type binding** (e.g. `fn (mut c ServerClient) …`, `fn (mut ctx context.Context) …`,
`fn (req &Request, mut wr ResponseWriter) …`). `builtin` has no such alias, so a
no-import repro is impossible; the minimal stable import is `net.jsonrpc`
(`Handler = fn (req &Request, mut wr ResponseWriter)`).

## Files

- Minimal stable repro (no `x.`, no `net.websocket`): `main.v` in **Minimal reproduction** above (uses `net.jsonrpc.Handler`).
- Real-world `net.websocket` repro (all three callbacks): `main.v` in **Second reproduction** above (uses `net.websocket.AcceptClientFn` / `SocketMessageFn2` / `SocketCloseFn2`).
- Same-module (no-import) counter-example: compiles cleanly, proving imports are required.
