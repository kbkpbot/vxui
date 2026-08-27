# TODO

## 1. 平台 Web 控件 → 独立轻量级浏览器进程（Native WebView Host）

### 现状分析

vxui 已将三大桌面平台的原生 web 控件包装成**独立轻量级浏览器子进程**，供
框架通过 WebSocket 复用同一套服务循环进行调用。核心设计：

- `WebViewDisplay`（embedded 家族）的 `embedded_spawn` 用 `os.fork()` /
  `CreateProcessW` **自重启一份同源 vxui 二进制**，以 `--vxui-host <pipe_fd>`
  进入 host 模式；
- 父进程通过私有控制管道写入 `HostHandshake`（页面 URL + 窗口几何 + token，
  token 不进命令行）与 `HostControl`（resize / move / title / close）指令；
- 子进程（host）独占自己的 OS 窗口与主线程（GTK main / Win32 loop /
  NSApplication run loop），页面由父框架经 WebSocket 提供；窗口关闭 = 子进程
  退出 = WS 客户端断开，框架据此正常退出。**进程隔离、零跨线程风险、无需系统
  浏览器**。

协议与符号契约（各平台一致）：`embedded_native_id()` / `embedded_spawn()` /
`host_run()`，定义于 `display.v` + 各 `display_<os>.v`。

### 各平台完成度

| 平台 | 后端 | 文件 | 状态 |
|------|------|------|------|
| Linux   | WebKitGTK | `display_linux.v`   | ✅ 已实现 |
| macOS   | WKWebView | `display_macos.v`   | ✅ 已实现 |
| Windows | WebView2  | `display_windows.v` | ✅ 已实现 |
| Android | android.webkit.WebView | `display_default.v`（桩） | ❌ 预留未实现 |

### 继续完善项（候选）

- [ ] **Android 平台实现（暂搁置）**：新增 `display_android.v`，经 JNI 把
      `android.webkit.WebView` 包装成同样的 host 子进程，补齐第四平台。
      （需 NDK/JNI 环境，本机 Linux 无法联编验证；用户暂决定不实现。）

## 2. 示例可运行性验证（本机 Xvfb 无头测试）

- [x] **修复配置覆盖清空 `close_timer_ms` 等字段**：`configfile.v` 的
      `apply_config_file` 无条件把 `multi_client` / `evict_on_new` /
      `close_timer_ms` 从 `FileConfig`（默认 `false`/`0`）覆盖回 `Config`，
      与注释"未出现在文件中的代码值应保留"相悖。当示例带 `vxui.json` 却不含
      这些键时（如 `examples/test`），`close_timer_ms` 被清零 → 应用启动即
      退出、示例无法运行。已改为可选字段（`?bool` / `?int`），仅当文件中存在
      对应键时才覆盖。`v -old-compiler build-module .` 与 `display_test.v` 均通过。
- [x] **示例运行验证**：在 Xvfb 无头环境下验证
      - `examples/test`（覆盖 `display.id=webkitgtk`）：`Frontend: native
        WebView [webkitgtk]` → `vxui host: window opened` → `Client authenticated`
        成功；
      - `examples/todo-app`（无 `vxui.json`，走 `auto` → webkitgtk）：同样窗口
        打开并认证成功。
- [x] **全量示例扫描（Xvfb 无头）**：对 `examples/` 下共 15 个示例逐一在 Xvfb +
      `-old-compiler` 下运行，全部 PASS（均出现 `window opened` 与
      `Client authenticated`）：test、packed、game-minesweeper、chat、
      element-plus、system-monitor、run-js-playground、markdown-editor、
      gallery、enchart、data-table、multi-window、todo-app、game-2048、
      game-gomoku。结论：原生 WebView 宿主进程在 Linux 上对所有示例均可正常
      拉起并接入。
      说明原生 WebView 宿主进程（即本次主题"独立轻量级浏览器进程"）在 Linux 上
      工作正常。`examples/test/vxui.json` 默认强制 `chrome`；无头环境下 chrome
      因无法获取 X display 失败属环境限制，框架本身正确启动了浏览器进程。
- [x] **清理过时文档/注释**（已完成）：
  - `README.md` 已准确描述三平台原生 WebView，无需改动；
  - `display_default.v` 注释原称 "macOS / Android today" 走桩 → 改为仅 Android；
  - `config.v` `webview` 字段注释原为 "reserved: in-process ... not yet
    implemented" → 改为描述三平台已实现 + android 预留；
  - `vxui.v` spawn 失败注释修正为指向 `android` 等未实现 id；
  - `doc/AGENTS.md` 多处 "reserved / not yet implemented / in-process" 已更正为
    三平台已实现、`android` 预留；
  - `doc/vxui.md`（vdoc 生成）同步订正 `DisplayFamily.embedded`、
    `WebViewConfig`、`WebViewDisplay`、`close_displays` 等处陈旧描述。
- [x] **host 进程"真正独立化"评估（结论）**：评估将同源二进制自重启
      （`--vxui-host`）改为真正独立的轻量 host 组件。
  - **现状已满足"独立轻量级浏览器进程"**：每个 host 是独立进程、独占主线程
    （GTK main / Win32 loop / NSApplication），与父框架经私有控制管道通信；
    Linux 子进程设 `PR_SET_PDEATHSIG`（`C.prctl(1,15)`）随父退出；进程隔离使
    WebView 故障不会拖垮应用；管道 EOF 时干净退出（见"控制管道健壮性"）。
  - **不改为独立二进制**：`run_packed` 单可执行分发依赖"自重启同一份二进制"，
    拆成独立 host 组件会破坏单文件分发，且需额外分发/定位 host 二进制。自重启
    方案在模块化与分发间已是更优折中，故**维持现状**，无需重构。
  - 关联加固：`close_displays` 关闭后已将 `display_session` 复位为 `none`
    （`displaymgr.v`），避免残留已关闭会话、便于后续重新开窗。
- [x] **多窗口 native 路径验证（bookkeeping）**：`display_test.v` 新增
      `test_open_window_multi_session_bookkeeping`，用 `FakeDisplay` /
      `FakeSession`（无需真实 GUI）验证：首个窗口存入 `display_session`、
      第二个窗口进入 `display_sessions`（不重用 `display_session`，避免
      `close_displays` 双重释放）、`close_displays` 恰好关闭两个窗口各一次。
      三平台真实 GUI 多窗口回归测试仍待有显示环境时手动验证。
- [x] **控制管道健壮性**：父进程异常退出 / 管道 EOF 时各平台 host 均干净
      退出。原仅 macOS 在 EOF 时发合成 `close`；Linux (`display_linux.v`
      `host_read_lines`) 与 Windows (`display_windows.v` `host_read_lines`)
      现已在管道 EOF 时派发合成 `close` 并退出，三平台行为一致。已 `v build-module` 验证 Linux 编译通过。
- [x] **host 生命周期日志**：三平台 host 均在窗口打开时打印
      `vxui host: window opened`，并在控制管道关闭退出时打印
      `vxui host: control pipe closed, closing window`（Linux/Windows 在
      `host_read_lines` EOF 分支，macOS 在 `host_read_lines` EOF 分支）。统一
      `LogLevel` 级日志（复用框架 logger）仍可作为后续增强，但基础生命周期
      可见性已具备。
- [x] **控制协议稳定性测试**：`display_test.v` 新增 `test_host_handshake_json_roundtrip`
      与 `test_host_control_json_roundtrip`，验证 `HostHandshake` / `HostControl`
      的 JSON 编解码往返一致（父子进程控制管道契约）。同时修复该测试文件既有的
      编译错误（`embedded_spawn` 缺 `WebViewDisplay` 首参、缺 `import x.json2`）。
      `v -old-compiler test display_test.v` 已通过。
