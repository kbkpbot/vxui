# vxui

> :warning: **Notice**:
>
>
> * vxui it's not a web-server solution or a framework, but it's an lightweight portable lib to use installed web browser as a user interface.
>
> * Currently, vxui is in it's alpha stage.


* vxui = browser + htmx/webui + websocket + v *

## Introduction

vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!

## Motivation

* Every desktop should has a installed web browser, and it's display it much better than native GUI. Because there are too many frontend designers in the world!
* When develop a desktop framework with HTML+CSS+JS, why should we integrate a web server? By using websocket, we can totally bypass the integerated web server!

## Features

* Cross-platform. It should be able to running on Windows/Linux/MacOS;
* Extensible. You can use any frontend framework develop your UI, all you need is just add some tags in your html files;
* Light weight. vxui contain only a pure-V websocket server, no web server;
* Powerful. vxui backend can communication with frondend bi-direction and realtime;
* Flexible. vxui provide websocket-based communication, you can totally define your own protocol, no longer limited by AJAX's request-response model.

## Inside vxui

![vxui](vxui.png)

* frontend: It is your installed web browser. And a modified vesion of [htmx](https://htmx.org) with vxui_htmx.js are all you need.
* backend: [v](https://vlang.io/)
* between frondend and backend, it is websocket.

- When you start your App, it will first look for a free port on your OS, then the websocket server listen on this port;
- The App will use command line spawn a process, start the web server, which will open your UI's first html file;
  Every your UI html file should include a JS agent file.
- The JS agent in your html file will use the port communication with backend websocket server;
- By using htmx or webui, every event catch by the JS agent(mouse click, keyup, text change...), will be transfered to your backend;
  Currently, vxui will replace all AJAX request in your htmx files with websocket communication.

## Example

```html
<script src="./js/htmx.js"></script>
<script src="./js/vxui_htmx.js"></script>
<span hx-ext="vxui_htmx"/>
  <!-- have a button POST a click via websocket -->
  <button hx-post="/clicked" hx-swap="outerHTML">
    Click Me
  </button>
```
The `hx-post` and `hx-swap` attributes tell htmx & vxui-htmx:

> "When a user clicks on this button, issue an websocket request to /clicked(`hx-post`), and replace the entire button with the response(`hx-swap`)"

And your websocket server will recieve this message:
```json
{"verb":"post","path":"/clicked","elt":"BUTTON","parameters":{},"HEADERS":{"HX-Request":"true","HX-Trigger":null,"HX-Trigger-Name":null,"HX-Target":null,"HX-Current-URL":"file:///home/kbkpbot/.vmodules/vxui/static/ss.html"}}
```

## Quick start

* install vxui
```sh
	v install --git https://github.com/kbkpbot/vxui.git
```
* check examples

## License

MIT license
