# vxui 示例扩充设计（system-monitor / chat / run-js-playground / data-table）

日期：2026-08-21
状态：已获口头批准，待用户审阅本文件

## 目标

为 vxui 补齐核心能力的示例覆盖（混合导向：能力演示 + 视觉效果），每个示例聚焦一组 API，
兼任该能力的集成验证素材。

## 共享约定

- 目录结构：`examples/<name>/main.v` + `ui/index.html` + `templates/*.html`（`$tmpl`）
- 技术栈：纯 htmx + 手写暗色 CSS；零第三方 JS 库（图表用内联 SVG，不引 ECharts）
- 每个示例含 `README.md`：演示要点、运行方式、涉及 API 清单
- `main.v` 顶部注释列出核心演示 API
- 所有示例保持 `v run main.v` 一键可跑；编译检查通过（`v -o /dev/null main.v`）

## 1. examples/system-monitor —— 实时系统监控仪表盘

**目的**：展示后端主动推送 + 多客户端同步，项目最出片的门面示例。

**后端**
- `multi_client = true`
- spawn goroutine 每 1s 采集并 `broadcast(oob_html)`：
  - CPU%：`/proc/stat` 两次采样差分（idle/total jiffies）
  - 内存：`/proc/meminfo`（MemTotal/MemAvailable）
  - 负载：`/proc/loadavg` 第一个字段
- 非 Linux（无 `/proc/stat`）：切换为正弦模拟数据，页面显示 "demo data" 徽标
- OOB HTML 含环形仪表与折线数据点，带 `hx-swap-oob`

**前端**
- 暗色仪表盘：三个 SVG 环形仪表（CPU/RAM/Load）+ CPU 历史 SVG polyline（保留 ~60 点）
- 顶部显示连接客户端数（`get_client_count()` 随推送更新）

**涉及 API**：`multi_client`、`broadcast`、`oob_update`、`get_client_count`

## 2. examples/chat —— 多窗口聊天室

**目的**：多客户端交互经典场景 + 生命周期事件钩子。

**后端**
- `multi_client = true`
- 昵称映射：`map[string]string`（client_id → nickname），mu 保护
- 路由：
  - `/join`（post）：记录昵称，广播"xxx 加入了聊天室"系统消息 + 刷新在线列表
  - `/send`（post）：把消息组装为 OOB 追加片段广播给所有客户端（含发送者，统一由广播回显）
- 离开检测完全依赖框架：客户端关窗时 `vxui-ws.js` 发送 `client_close`，服务端触发
  `on_event(.client_disconnected)` 钩子清理昵称映射并广播"xxx 离开了"
- 在线列表：`get_clients()` + 昵称映射渲染

**前端**
- 左侧在线用户列表，右侧消息流（OOB `beforeend` 追加）+ 输入框
- 系统消息与用户消息视觉区分

**涉及 API**：`broadcast`、`get_clients`、`on_event`、多客户端

## 3. examples/run-js-playground —— 后端驱动前端

**目的**：旗舰功能 `run_js` 的专属演示。

**后端**
- 自定义 `js_sandbox`（如追加禁用模式）展示配置能力
- 按钮 handler 各自调用 `run_js(...)` 并把「执行的 JS + 返回值/错误」格式化后经 OOB 追加到日志面板：
  - 读页面标题：`document.title`
  - 平滑滚顶：`window.scrollTo({top:0,behavior:'smooth'})`（fire-and-forget，timeout=0）
  - 弹 toast：注入一次性 DOM 元素
  - 切换主题色：设置 CSS 变量（多窗口同步的意外收益——日志面板同步展示各端结果差异）
  - 获取 UA：`navigator.userAgent`
  - 故意超时示例：执行 `while(1){}` 类长任务触发 js_timeout 错误路径展示
- 目标选择：工具栏下拉框列出 `get_clients()`（默认"第一个窗口"），选中即用
  `run_js_client(client_id, ...)`，默认项走 `run_js(...)`；下拉随推送周期刷新
- 日志条目带时间戳与成功/失败配色

**前端**
- 左侧按钮组，右侧等宽字体控制台面板

**涉及 API**：`run_js`、`run_js_client`（多开窗口时定向）、`js_sandbox`、错误处理

## 4. examples/data-table —— 服务端数据表格

**目的**：真实业务最常用的服务端分页/搜索/排序模式参考。

**后端**
- 内存生成 ~200 行模拟员工数据（id/姓名/部门/薪资/入职日期/状态），启动时生成一次
- 单一 `/query`（post）路由，接收 `page/page_size/q/sort_col/sort_dir/status` 参数，
  过滤→排序→切片→只返回 `<tbody>` 片段；同时 OOB 更新分页信息栏
- 全部无状态（参数驱动），刷新/多窗口天然一致

**前端**
- 工具栏：搜索框（`hx-trigger="keyup changed delay:300ms"`）、状态下拉
- 表头点击排序（指示当前排序方向箭头）；分页控件（上一页/下一页/页码信息）

**涉及 API**：`parameters` 处理、`hx-trigger` 高级用法、动词属性路由

## 实施顺序

1. system-monitor（先打通 broadcast 推送基础设施）
2. chat（复用 broadcast，叠加事件钩子）
3. run-js-playground
4. data-table

每个完成后立即编译验证 + 实际运行冒烟，全部完成后统一在 AGENTS.md 示例清单中登记。

## 明确不做

- 不引入任何第三方前端库
- 不做持久化存储（chat 昵称、表格数据均内存态）
- 不改框架源码（若发现 bug 单独报告，不在本批次修）
