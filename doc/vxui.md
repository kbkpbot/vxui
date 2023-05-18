# module vxui



## Contents
- [VXUI](#VXUI)
  - [run](#run)

## VXUI
```v
struct VXUI {
mut:
	ws_port u16
	ws      websocket.Server
}
```

VXUI is the main struct of vxui

[[Return to contents]](#Contents)

## run
```v
fn (mut vv VXUI) run(html_filename string, js_filename string)
```

run open the `html_filename` and modify the `js_filename`(vxui-htmx.js)

[[Return to contents]](#Contents)

#### Powered by vdoc. Generated on: 18 May 2023 10:52:33
