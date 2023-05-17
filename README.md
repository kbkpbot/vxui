# vxui

> :warning: **Notice**:
>
>
> * vxui it's not a web-server solution or a framework, but it's an lightweight portable lib to use installed web browser as a user interface.
>
> * Currently, vxui is under heavily develop.


* vxui = browser + htmx + websocket + v *

## Introduction

vxui is a desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!

## Motivation

* Every desktop should has a installed web browser, and it's display it much better than native GUI. Because there are too many frontend designers in the world!
* When develop a desktop framework with HTML5+CSS+JS, why should we integrate a web server? By using websocket, we can totally bypass the integerated web server!


## Inside vxui

* frontend: It is your installed web browser. And a modified vesion of htmx(https://htmx.org) with vxui_ws.js are all you need.
* backend: v(https://github.com/vlang/v)
* between frondend and backend, it is websocket.

## Quick start

* install vxui
```sh
	v install https://github.com/kbkpbot/vxui.git
```
* check examples

## License

MIT license
