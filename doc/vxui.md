# module vxui
vxui is a cross-platform desktop UI framework which use your browser as screen, and use V lang as backend. It reply on Websocket, no http/https, no web server!


## Contents
- [run](#run)
- [Context](#Context)

## run
```v
fn run[T](mut app T, html_filename string) !
```
run open the `html_filename`

[[Return to contents]](#Contents)

## Context
```v
struct Context {
mut:
	ws_port u16
	ws      websocket.Server
	routes  map[string]Route
pub mut:
	logger &log.Logger = &log.Logger(&log.Log{})
}
```
Context is the main struct of vxui

[[Return to contents]](#Contents)

#### Powered by vdoc. Generated on: 19 Oct 2024 21:03:51
