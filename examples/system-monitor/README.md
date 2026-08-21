# system-monitor 实时系统监控仪表盘

后端每秒采集 CPU/内存/负载并广播到所有窗口，多开几个浏览器窗口即可看到同步刷新。

## 演示 API

| API | 用途 |
|-----|------|
| `multi_client` | 允许多个浏览器窗口同时连接 |
| `broadcast` | 向全部客户端推送 |
| `oob_update` 命令 | 推送 OOB HTML 片段 |
| `get_client_count` | 显示在线窗口数 |

## 运行

```bash
v run main.v
```

Linux 下展示 `/proc/stat`、`/proc/meminfo`、`/proc/loadavg` 真实数据；
其他平台自动降级为平滑正弦模拟数据。
