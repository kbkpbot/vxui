# vxui 项目指南

## 项目概述

**vxui** 是一个跨平台的桌面 UI 框架，使用 V 语言作为后端，浏览器作为显示界面。它通过 WebSocket 进行前后端通信，无需 HTTP/HTTPS 服务器。

### 核心理念
- 利用每个桌面系统都自带的浏览器作为 UI 显示层
- 使用 WebSocket 替代传统的 HTTP 请求，实现真正的双向实时通信
- 前端可以使用 HTML + CSS + JS 开发，配合 htmx 框架
- 后端使用纯 V 语言编写

### 技术栈
- **后端**: V 语言 (vlang.io)
- **前端**: HTML + CSS + JavaScript
- **通信**: WebSocket
- **前端框架**: htmx (修改版) + vxui-htmx.js

---

## 项目结构

```
/home/mars/.vmodules/vxui/
├── vxui.v              # 主框架源码，包含 WebSocket 服务器和路由逻辑
├── v.mod               # V 模块定义文件
├── README.md           # 项目说明文档
├── LICENSE             # MIT 许可证
├── vxui.png            # 架构示意图
├── doc/
│   └── vxui.md         # API 文档 (由 vdoc 生成)
├── js/
│   ├── vxui-htmx.js    # vxui htmx 扩展，处理 WebSocket 通信
│   ├── vxui-webui.js   # WebUI 模式的 JavaScript 代理
│   ├── htmx.js         # htmx 库 (修改版)
│   └── ajaxhook.js     # AJAX 拦截库
└── examples/
    ├── test/           # 基础示例：表单处理、按钮交互
    └── enchart/        # 高级示例：ECharts 实时数据可视化
```

---

## 核心架构

### 工作流程

1. **启动应用**:
   - 寻找可用端口
   - 启动 WebSocket 服务器监听该端口
   - 启动 Chrome 浏览器，加载初始 HTML 文件

2. **通信机制**:
   - 前端通过 `vxui-htmx.js` 与后端建立 WebSocket 连接
   - 所有 htmx 的 AJAX 请求被拦截并转换为 WebSocket 消息
   - 后端处理请求并返回 HTML 片段，前端进行局部更新

3. **消息格式**:
   ```json
   {
     "verb": "post",
     "path": "/clicked",
     "elt": "BUTTON",
     "parameters": {},
     "HEADERS": {
       "HX-Request": "true",
       "HX-Trigger": null,
       "HX-Trigger-Name": null,
       "HX-Target": null,
       "HX-Current-URL": "file:///..."
     }
   }
   ```

### 关键组件

| 组件 | 描述 |
|------|------|
| `Context` | 主结构体，包含 WebSocket 端口、服务器实例、路由映射 |
| `Route` | 路由定义，包含 HTTP 动词和路径 |
| `Verb` | 枚举类型：get, post, put, delete, patch, any_verb |
| `run[T]()` | 启动函数，打开浏览器并运行事件循环 |

---

## 使用方法

### 安装

```bash
v install --git https://github.com/kbkpbot/vxui.git
```

### 创建应用

```v
module main

import vxui
import x.json2

// 1. 继承 vxui.Context
struct App {
    vxui.Context
mut:
    counter int
}

// 2. 定义路由处理器
@['/submit']  // 指定路径
fn (mut app App) submit(message map[string]json2.Any) string {
    app.counter++
    // 返回 HTML 片段，支持 hx-swap-oob 进行局部更新
    return '<div id="result" hx-swap-oob="true">Count: ${app.counter}</div>'
}

// 3. 省略属性时使用函数名作为路径
fn (mut app App) hello(message map[string]json2.Any) string {
    return '<div>Hello from vxui!</div>'
}

fn main() {
    mut app := App{}
    app.close_timer = 1000  // 无客户端时 1000ms 后自动关闭
    app.logger.set_level(.debug)
    vxui.run(mut app, './ui/index.html')!
}
```

### 前端 HTML

```html
<!DOCTYPE html>
<html>
<head>
    <script src="./js/htmx.js"></script>
    <script src="./js/ajaxhook.js"></script>
    <script src="./js/vxui-htmx.js"></script>
</head>
<body>
    <!-- hx-post 触发 WebSocket 请求到 /submit -->
    <button hx-post="/submit" hx-swap="outerHTML">
        Click Me
    </button>
    <div id="result"></div>
</body>
</html>
```

---

## 关键配置选项

### Context 结构体

```v
struct Context {
mut:
    ws_port u16              // WebSocket 监听端口
    ws      websocket.Server // WebSocket 服务器实例
    routes  map[string]Route // 路由映射
pub mut:
    close_timer int = 50     // 无浏览器连接时自动关闭的等待时间(ms)
    logger &log.Log          // 日志记录器
}
```

### 属性标签

- `['/path']` - 指定路由路径
- `['get']`, `['post']`, `['put']`, `['delete']`, `['patch']` - 指定 HTTP 动词
- 可组合使用: `['/api', 'post']`

---

## 示例说明

### examples/test - 基础交互示例

演示功能:
- 表单提交与数据绑定
- 动态编辑/取消编辑模式切换
- 多参数处理
- 快捷键触发 (alt+shift+D)

### examples/enchart - 实时图表示例

演示功能:
- 每秒从后端获取随机数据
- 使用 ECharts 渲染实时图表
- JSON 数据通信

---

## 开发规范

### 后端开发

1. **结构体定义**: 必须嵌入 `vxui.Context`
2. **处理器函数**:
   - 接收 `(mut app T)` 作为接收器
   - 参数为 `message map[string]json2.Any`
   - 返回 `string` (HTML 片段)
3. **返回值**: 使用 `hx-swap-oob="true"` 进行带外交换更新指定元素

### 前端开发

1. **必须引入的脚本**:
   - `htmx.js` - 核心库
   - `ajaxhook.js` - AJAX 拦截
   - `vxui-htmx.js` - vxui 扩展

2. **htmx 属性**:
   - `hx-post`, `hx-get`, `hx-put`, `hx-delete` - 触发请求
   - `hx-swap` - 指定替换方式 (innerHTML, outerHTML, beforeend 等)
   - `hx-swap-oob` - 带外交换，更新非触发元素
   - `hx-trigger` - 自定义触发条件

---

## 构建与运行

### 运行示例

```bash
# 进入示例目录
cd examples/test

# 运行示例
v run main.v

# 或指定 HTML 文件
v run main.v ./ui/custom.html
```

### 开发调试

```v
// 启用详细日志
app.logger.set_level(.debug)
app.logger.set_output_stream(os.stderr())
app.logger.set_short_tag(true)
app.logger.set_custom_time_format('HH:mm:ss')
```

---

## 注意事项

1. **Alpha 阶段**: 项目处于早期开发阶段，API 可能变动
2. **浏览器支持**: 目前主要支持 Chrome (通过特定启动参数)
3. **无 HTTP 服务器**: 所有通信通过 WebSocket，文件通过 `file://` 协议加载
4. **自动关闭**: 当没有浏览器客户端连接时，应用会在 `close_timer` 时间后自动退出
5. **Chrome 启动参数**: 使用独立的用户数据目录，禁用缓存和扩展

---

## 许可证

MIT License

---

## 相关链接

- 项目仓库: https://github.com/kbkpbot/vxui
- V 语言: https://vlang.io
- htmx: https://htmx.org
