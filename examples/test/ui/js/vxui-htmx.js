/*
vxui-htmx WebSockets Extension
============================
This extension adds support for vxui WebSockets to htmx.
 */

(function () {

    /** @type {import("../htmx").HtmxInternalApi} */
    var api;
    var vxui_ws;
    var VERBS = ['get', 'post', 'put', 'delete', 'patch'];

    htmx.defineExtension("vxui-htmx", {

        /**
         * init is called once, when this extension is first registered.
         * @param {import("../htmx").HtmxInternalApi} apiRef
         */
        init: function (apiRef) {

            // Store reference to internal API
            api = apiRef;

            // Default function for creating new EventSource objects
            if (!htmx.createWebSocket) {
                htmx.createWebSocket = createWebSocket;
            }

            // Default setting for reconnect delay
            if (!htmx.config.wsReconnectDelay) {
                htmx.config.wsReconnectDelay = "full-jitter";
            }
        },

        /**
         * onEvent handles all events passed to this extension.
         *
         * @param {string} name
         * @param {Event} evt
         */
        onEvent: function (name, evt) {

            switch (name) {
                // Try to close the socket when elements are removed
            case "htmx:beforeCleanupElement":

                var internalData = api.getInternalData(evt.target)

                    if (internalData.webSocket) {
                        internalData.webSocket.close();
                    }
                    return;

                // Try to create websockets when elements are processed
            case "htmx:afterProcessNode":
                var parent = evt.target;

                forEach(queryAttributeOnThisOrChildren(parent, "hx-ext"), function (child) {
                    ensureWebSocket(child);
                });

                forEach(VERBS, function (verb) {
                    forEach(queryAttributeOnThisOrChildren(parent, "hx-" + verb), function (child) {
                        processWebSocketSend(vxui_ws, child)
                    })
                });
            }
        }
    });

    /**
     * ensureWebSocket creates a new WebSocket on the designated element, using
     * the element's "hx-ext=vxui_ws" attribute.
     * @param {HTMLElement} socketElt
     * @returns
     */
    function ensureWebSocket(socketElt) {
        if (api.getAttributeValue(socketElt, "hx-ext") != "vxui-htmx")
            return;
        // If the element containing the WebSocket connection no longer exists, then
        // do not connect/reconnect the WebSocket.
        if (!api.bodyContains(socketElt)) {
            return;
        }

        // Get the source straight from the element's value
        var wssSource = "ws://localhost:" + vxui_ws_port + "/echo"

            var socketWrapper = createWebsocketWrapper(socketElt, function () {
            return htmx.createWebSocket(wssSource)
        });

        socketWrapper.addEventListener('message', function (event) {
            if (maybeCloseWebSocketSource(socketElt)) {
                return;
            }

            var response = event.data;
	    if (response == "pong")
		return;
            console.log(response);
            if (!api.triggerEvent(socketElt, "htmx:wsBeforeMessage", {
                    message: response,
                    socketWrapper: socketWrapper.publicInterface
                })) {
                return;
            }

            api.withExtensions(socketElt, function (extension) {
                response = extension.transformResponse(response, null, socketElt);
            });

            var settleInfo = api.makeSettleInfo(socketElt);
            var fragment = api.makeFragment(response);

	    //console.log(fragment);
		/*
						var xhr = new FakeXMLHttpRequest();
						xhr.respond(200, { 'Content-Type': 'application/json' }, '{"key":"value"}');
						console.log(xhr);
						target = api.getTarget(child);
						var elt_data = api.getInternalData(child)
						console.log(elt_data);
						var path = api.getAttributeValue(child, 'hx-' + verb);
						var responseInfo = {
							xhr: xhr,
							target: target,
							//requestConfig: requestConfig,
							etc: {},
							boosted: false,
							pathInfo: {
								requestPath: path,
								finalRequestPath: path,
								anchor: null
							}
						};
						
						console.log(responseInfo);

						api.handleAjaxResponse(child, responseInfo);
						
*/
            if (fragment.children.length) {
                var children = Array.from(fragment.children);
				console.log(children);
                for (var i = 0; i < children.length; i++) {
                    api.oobSwap(api.getAttributeValue(children[i], "hx-swap-oob") ||
                        "true", children[i], settleInfo);
                }
            }

            api.settleImmediately(settleInfo.tasks);
            api.triggerEvent(socketElt, "htmx:wsAfterMessage", {
                message: response,
                socketWrapper: socketWrapper.publicInterface
            })
        });

        // Put the WebSocket into the HTML Element's custom data.
        api.getInternalData(socketElt).webSocket = socketWrapper;
        vxui_ws = socketElt;
    }

    /**
     * @typedef {Object} WebSocketWrapper
     * @property {WebSocket} socket
     * @property {Array<{message: string, sendElt: Element}>} messageQueue
     * @property {number} retryCount
     * @property {(message: string, sendElt: Element) => void} sendImmediately sendImmediately sends message regardless of websocket connection state
     * @property {(message: string, sendElt: Element) => void} send
     * @property {(event: string, handler: Function) => void} addEventListener
     * @property {() => void} handleQueuedMessages
     * @property {() => void} init
     * @property {() => void} close
     */
    /**
     *
     * @param socketElt
     * @param socketFunc
     * @returns {WebSocketWrapper}
     */
    function createWebsocketWrapper(socketElt, socketFunc) {
        var wrapper = {
            socket: null,
            messageQueue: [],
            retryCount: 0,

            /** @type {Object<string, Function[]>} */
            events: {},

            addEventListener: function (event, handler) {
                if (this.socket) {
                    this.socket.addEventListener(event, handler);
                }

                if (!this.events[event]) {
                    this.events[event] = [];
                }

                this.events[event].push(handler);
            },

            sendImmediately: function (message, sendElt) {
                if (!this.socket) {
                    api.triggerErrorEvent()
                }
                if (sendElt && api.triggerEvent(sendElt, 'htmx:wsBeforeSend', {
                        message: message,
                        socketWrapper: this.publicInterface
                    })) {
                    this.socket.send(message);
                    sendElt && api.triggerEvent(sendElt, 'htmx:wsAfterSend', {
                        message: message,
                        socketWrapper: this.publicInterface
                    })
                }
            },

            send: function (message, sendElt) {
                if (this.socket.readyState !== this.socket.OPEN) {
                    this.messageQueue.push({
                        message: message,
                        sendElt: sendElt
                    });
                } else {
                    this.sendImmediately(message, sendElt);
                }
            },

            handleQueuedMessages: function () {
                while (this.messageQueue.length > 0) {
                    var queuedItem = this.messageQueue[0]
                        if (this.socket.readyState === this.socket.OPEN) {
                            this.sendImmediately(queuedItem.message, queuedItem.sendElt);
                            this.messageQueue.shift();
                        } else {
                            break;
                        }
                }
            },

            init: function () {
                if (this.socket && this.socket.readyState === this.socket.OPEN) {
                    // Close discarded socket
                    this.socket.close()
                }

                // Create a new WebSocket and event handlers
                /** @type {WebSocket} */
                var socket = socketFunc();

                // The event.type detail is added for interface conformance with the
                // other two lifecycle events (open and close) so a single handler method
                // can handle them polymorphically, if required.
                api.triggerEvent(socketElt, "htmx:wsConnecting", {
                    event: {
                        type: 'connecting'
                    }
                });

                this.socket = socket;

                socket.onopen = function (e) {
                    wrapper.retryCount = 0;
                    api.triggerEvent(socketElt, "htmx:wsOpen", {
                        event: e,
                        socketWrapper: wrapper.publicInterface
                    });
                    wrapper.handleQueuedMessages();
                }

                socket.onclose = function (e) {
                    // If socket should not be connected, stop further attempts to establish connection
                    // If Abnormal Closure/Service Restart/Try Again Later, then set a timer to reconnect after a pause.
                    if (!maybeCloseWebSocketSource(socketElt) &&
                        [1006, 1012, 1013].indexOf(e.code) >= 0) {
                        var delay = getWebSocketReconnectDelay(wrapper.retryCount);
                        setTimeout(function () {
                            wrapper.retryCount += 1;
                            wrapper.init();
                        }, delay);
                    }

                    // Notify client code that connection has been closed. Client code can inspect `event` field
                    // to determine whether closure has been valid or abnormal
                    api.triggerEvent(socketElt, "htmx:wsClose", {
                        event: e,
                        socketWrapper: wrapper.publicInterface
                    })
                };

                socket.onerror = function (e) {
                    api.triggerErrorEvent(socketElt, "htmx:wsError", {
                        error: e,
                        socketWrapper: wrapper
                    });
                    maybeCloseWebSocketSource(socketElt);
                };

                var events = this.events;
                Object.keys(events).forEach(function (k) {
                    events[k].forEach(function (e) {
                        socket.addEventListener(k, e);
                    })
                });
            },

            close: function () {
                this.socket.close()
            }
        }

        wrapper.init();

        wrapper.publicInterface = {
            send: wrapper.send.bind(wrapper),
            sendImmediately: wrapper.sendImmediately.bind(wrapper),
            queue: wrapper.messageQueue
        };

        return wrapper;
    }

    /**
     * processWebSocketSend adds event listeners to the <form> element so that
     * messages can be sent to the WebSocket server when the form is submitted.
     * @param {HTMLElement} socketElt
     * @param {HTMLElement} sendElt
     */
    function processWebSocketSend(socketElt, sendElt) {
        var nodeData = api.getInternalData(sendElt);
        var triggerSpecs = api.getTriggerSpecs(sendElt);
        triggerSpecs.forEach(function (ts) {
            api.addTriggerHandler(sendElt, ts, nodeData, function (elt, evt) {
                if (maybeCloseWebSocketSource(socketElt)) {
                    return;
                }

                /** @type {WebSocketWrapper} */
                var socketWrapper = api.getInternalData(socketElt).webSocket;
                var headers = api.getHeaders(sendElt, api.getTarget(sendElt));
                var results = api.getInputValues(sendElt, 'post');
                var errors = results.errors;
                var rawParameters = results.values;
                var expressionVars = api.getExpressionVars(sendElt);
                var allParameters = api.mergeObjects(rawParameters, expressionVars);
                var filteredParameters = api.filterValues(allParameters, sendElt);

                var sendConfig = {
                    parameters: filteredParameters,
                    unfilteredParameters: allParameters,
                    headers: headers,
                    errors: errors,

                    triggeringEvent: evt,
                    messageBody: undefined,
                    socketWrapper: socketWrapper.publicInterface
                };

                api.triggerEvent(elt, 'htmx:beforeRequest', sendConfig);

                //if (!api.triggerEvent(elt, 'htmx:wsConfigSend', sendConfig)) {
                //  return;
                //}

                if (errors && errors.length > 0) {
                    api.triggerEvent(elt, 'htmx:validation:halted', errors);
                    return;
                }

                var body = sendConfig.messageBody;
                if (body === undefined) {
                    var toSend = {};
                    forEach(VERBS, function (verb) {
                        var path = api.getAttributeValue(elt, "hx-" + verb);
                        if (path != undefined) {
                            toSend['verb'] = verb;
                            toSend['path'] = path;
                        }
                    })
                    toSend['elt'] = elt.tagName;

                    toSend['parameters'] = Object.assign({}, sendConfig.parameters);
                    if (sendConfig.headers)
                        toSend['HEADERS'] = sendConfig.headers;
                    body = JSON.stringify(toSend);
                }

                socketWrapper.send(body, elt);

                if (api.shouldCancel(evt, elt)) {
                    evt.preventDefault();
                }
            });
        });
    }

    /**
     * getWebSocketReconnectDelay is the default easing function for WebSocket reconnects.
     * @param {number} retryCount // The number of retries that have already taken place
     * @returns {number}
     */
    function getWebSocketReconnectDelay(retryCount) {

        /** @type {"full-jitter" | ((retryCount:number) => number)} */
        var delay = htmx.config.wsReconnectDelay;
        if (typeof delay === 'function') {
            return delay(retryCount);
        }
        if (delay === 'full-jitter') {
            var exp = Math.min(retryCount, 6);
            var maxDelay = 1000 * Math.pow(2, exp);
            return maxDelay * Math.random();
        }

        logError('htmx.config.wsReconnectDelay must either be a function or the string "full-jitter"');
    }

    /**
     * maybeCloseWebSocketSource checks to the if the element that created the WebSocket
     * still exists in the DOM.  If NOT, then the WebSocket is closed and this function
     * returns TRUE.  If the element DOES EXIST, then no action is taken, and this function
     * returns FALSE.
     *
     * @param {*} elt
     * @returns
     */
    function maybeCloseWebSocketSource(elt) {
        if (!api.bodyContains(elt)) {
            api.getInternalData(elt).webSocket.close();
            return true;
        }
        return false;
    }

    /**
     * createWebSocket is the default method for creating new WebSocket objects.
     * it is hoisted into htmx.createWebSocket to be overridden by the user, if needed.
     *
     * @param {string} url
     * @returns WebSocket
     */
    function createWebSocket(url) {
        var sock = new WebSocket(url, []);
        sock.binaryType = htmx.config.wsBinaryType;
        return sock;
    }

    /**
     * queryAttributeOnThisOrChildren returns all nodes that contain the requested attributeName, INCLUDING THE PROVIDED ROOT ELEMENT.
     *
     * @param {HTMLElement} elt
     * @param {string} attributeName
     */
    function queryAttributeOnThisOrChildren(elt, attributeName) {

        var result = []

        // If the parent element also contains the requested attribute, then add it to the results too.
        if (api.hasAttribute(elt, attributeName)) {
            result.push(elt);
        }

        // Search all child nodes that match the requested attribute
        elt.querySelectorAll("[" + attributeName + "], [data-" + attributeName +
            "], [data-hx-ws], [hx-ws]").forEach(function (node) {
            result.push(node)
        })

        return result
    }

    /**
     * @template T
     * @param {T[]} arr
     * @param {(T) => void} func
     */
    function forEach(arr, func) {
        if (arr) {
            for (var i = 0; i < arr.length; i++) {
                func(arr[i]);
            }
        }
    }
})();
// Please note: this `vxui_ws_port` will be modified by app running!
const vxui_ws_port = 19399;
