# chat 多窗口聊天室

开多个窗口、分别取昵称加入即可互聊；关闭窗口时其余窗口收到离开提示。

## 演示 API

| API | 用途 |
|-----|------|
| `multi_client` / `broadcast` | 消息扇出到所有窗口 |
| `on_event(.client_disconnected)` | 断连清理昵称并广播离开消息 |

## 实现要点

框架请求中不含 client_id，页面监听 `vxui:authenticated` 事件读取
`window.vxuiWs.getClientId()` 写入隐藏域随表单提交。

## 运行

```bash
v run main.v
```
