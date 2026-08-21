# data-table 服务端数据表格

200 行模拟员工数据的无状态查询：搜索（300ms 防抖）、状态下拉、点表头排序、分页。
每次请求携带完整参数，天然支持多窗口一致视图。

首屏数据：搜索框带 `hx-trigger="load, ..."`，页面打开即触发首次 `/query`，表格无需等待交互就有数据。

## 演示 API

| 能力 | 实现 |
|------|------|
| `hx-trigger` 高级用法 | `keyup changed delay:300ms` 防抖搜索 + `load` 首屏触发 |
| parameters 处理 | `/query` 解析 q/status/sort/dir/page |
| 动词属性路由 | `@['/query']` POST |

## 运行

```bash
v run main.v
```
