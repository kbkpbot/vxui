# run-js-playground 后端驱动前端

点击按钮 → 后端 `run_js` 执行 JavaScript → 结果经 `broadcast` 同步到所有窗口的日志面板。

## 演示 API

| API | 用途 |
|-----|------|
| `run_js` | 执行 JS 并取回返回值 |
| `run_js_client` | 定向某客户端执行（下拉框选择目标窗口） |
| 超时与错误处理 | 「超时演示」按钮触发 `js_timeout` 错误路径 |
| `broadcast` + `oob_update` | 日志面板多窗口同步 |
| `get_clients` 命令 | 页面枚举在线客户端（vxui-ws.js ≥ 本版本） |

## 说明

- 「刷新目标列表」按钮 / 认证后自动拉取在线客户端 ID，选中即定向执行。
- 沙箱可用 `app.config.js_sandbox` 配置（禁用模式、结果大小上限、禁止模式列表）。

## 运行

```bash
v run main.v
```
