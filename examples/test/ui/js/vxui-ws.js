/*
vxui-ws - WebSocket Extension for vxui
============================================
This extension intercepts all htmx AJAX requests and routes them through WebSocket.
Designed for vxui framework - a desktop UI framework using browser as display layer.

Features:
- Token authentication
- Automatic reconnection
- JavaScript execution from backend
- Multi-client support

Usage:
  <script src="htmx.js"></script>
  <script src="vxui-ws.js"></script>
  <body hx-ext="vxui-ws">
    <!-- All htmx requests will use WebSocket -->
  </body>
*/

(function() {
    'use strict'

    /** @type {import("../htmx").HtmxInternalApi} */
    var api

    // WebSocket connection state
    var socket = null
    var socketWrapper = null
    var messageQueue = []
    var pendingRequests = {}  // rpcID -> {resolve, reject, elt, target, swapSpec, settle_info}
    var rpcCounter = 0
    var retryCount = 0
    var isConnecting = false
    var isAuthenticated = false
    var clientId = null
    var token = null

    // Configuration
    var config = {
        reconnectDelay: 'full-jitter',
        connectTimeout: 5000,
        debug: true
    }

    /**
     * Log debug messages
     */
    function log() {
        if (config.debug && console.debug) {
            console.debug.apply(console, ['[vxui-ws]'].concat(Array.from(arguments)))
        }
    }

    /**
     * Generate unique RPC ID (integer for vxui backend compatibility)
     */
    function generateRpcID() {
        return Date.now()
    }

    /**
     * Get URL parameter by name
     */
    function getUrlParam(name) {
        var search = location.search
        if (search.indexOf('?') !== -1) {
            var params = search.substring(1).split('&')
            for (var i = 0; i < params.length; i++) {
                var pair = params[i].split('=')
                if (pair[0] === name) {
                    return decodeURIComponent(pair[1])
                }
            }
        }
        return null
    }

    /**
     * Get WebSocket port from URL parameters
     */
    function getWsPort() {
        return getUrlParam('vxui_ws_port') || '8080'
    }

    /**
     * Get security token from URL parameters
     */
    function getToken() {
        return getUrlParam('vxui_token') || ''
    }

    /**
     * Create WebSocket URL
     */
    function getWsUrl() {
        var port = getWsPort()
        return 'ws://localhost:' + port + '/echo'
    }

    /**
     * Calculate reconnect delay
     */
    function getReconnectDelay() {
        var delay = config.reconnectDelay
        if (typeof delay === 'function') {
            return delay(retryCount)
        }
        if (delay === 'full-jitter') {
            var exp = Math.min(retryCount, 6)
            var maxDelay = 1000 * Math.pow(2, exp)
            return maxDelay * Math.random()
        }
        return 1000
    }

    /**
     * Convert parameters to plain object
     */
    function paramsToObject(params) {
        if (!params) {
            return {}
        }
        // Handle FormData
        if (params instanceof FormData) {
            var obj = {}
            params.forEach(function(value, key) {
                if (obj[key] !== undefined) {
                    if (!Array.isArray(obj[key])) {
                        obj[key] = [obj[key]]
                    }
                    obj[key].push(value)
                } else {
                    obj[key] = value
                }
            })
            return obj
        }
        // Handle formDataProxy with toJSON
        if (typeof params.toJSON === 'function') {
            return params.toJSON()
        }
        // Handle plain object
        return params
    }

    /**
     * Send authentication message
     */
    function sendAuth() {
        token = getToken()
        if (!token) {
            log('No token found, skipping auth')
            isAuthenticated = true
            processQueue()
            return
        }
        
        var authMsg = {
            cmd: 'auth',
            token: token
        }
        socket.send(JSON.stringify(authMsg))
        log('Sent auth request with token')
    }

    /**
     * Handle incoming command messages
     */
    function handleCommand(msg) {
        switch (msg.cmd) {
            case 'auth_ok':
                isAuthenticated = true
                clientId = msg.client_id
                log('Authentication successful, client_id:', clientId)
                processQueue()
                api.triggerEvent(document.body, 'vxui:authenticated', { clientId: clientId })
                break
            
            case 'run_js':
                executeJs(msg.js_id, msg.script)
                break
        }
    }

    /**
     * Execute JavaScript and return result
     */
    function executeJs(jsId, script) {
        var result = ''
        var error = null
        
        try {
            result = eval(script)
            if (result === undefined) {
                result = ''
            }
            if (typeof result === 'object') {
                result = JSON.stringify(result)
            }
            result = String(result)
        } catch (e) {
            error = e.message
            log('JS execution error:', error)
        }

        var response = {
            cmd: 'js_result',
            js_id: jsId,
            result: result,
            error: error
        }
        socket.send(JSON.stringify(response))
    }

    /**
     * Initialize WebSocket connection
     */
    function initWebSocket() {
        if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
            return
        }

        if (isConnecting) {
            return
        }

        isConnecting = true
        var wsUrl = getWsUrl()
        log('Connecting to', wsUrl)

        try {
            socket = new WebSocket(wsUrl)

            socket.onopen = function(e) {
                log('WebSocket connected')
                isConnecting = false
                retryCount = 0
                socketWrapper = { socket: socket }
                
                // Send authentication
                sendAuth()

                api.triggerEvent(document.body, 'vxui:wsOpen', { url: wsUrl })
            }

            socket.onclose = function(e) {
                log('WebSocket closed', e.code, e.reason)
                isConnecting = false
                isAuthenticated = false
                socket = null
                socketWrapper = null

                api.triggerEvent(document.body, 'vxui:wsClose', { code: e.code, reason: e.reason })

                // Auto reconnect for abnormal closure
                if ([1006, 1012, 1013].indexOf(e.code) >= 0) {
                    var delay = getReconnectDelay()
                    log('Reconnecting in', delay, 'ms')
                    setTimeout(function() {
                        retryCount++
                        initWebSocket()
                    }, delay)
                }
            }

            socket.onerror = function(e) {
                log('WebSocket error', e)
                isConnecting = false

                api.triggerErrorEvent(document.body, 'vxui:wsError', { error: e })

                for (var rpcID in pendingRequests) {
                    var pending = pendingRequests[rpcID]
                    if (pending.reject) {
                        pending.reject(new Error('WebSocket error'))
                    }
                }
                pendingRequests = {}
            }

            socket.onmessage = function(e) {
                // Handle pong
                if (e.data === 'pong') {
                    log('Received pong')
                    return
                }

                try {
                    var response = JSON.parse(e.data)
                    log('Received response', response)

                    // Handle command messages
                    if (response.cmd) {
                        handleCommand(response)
                        return
                    }

                    // Handle RPC responses
                    var rpcID = response.rpcID
                    var pending = pendingRequests[rpcID]

                    if (pending) {
                        delete pendingRequests[rpcID]
                        handleResponse(pending, response.data)
                    } else {
                        log('No pending request for rpcID:', rpcID)
                    }
                } catch (err) {
                    log('Error parsing response:', err)
                    api.triggerErrorEvent(document.body, 'vxui:wsParseError', { error: err, data: e.data })
                }
            }

        } catch (err) {
            log('Error creating WebSocket:', err)
            isConnecting = false
        }
    }

    /**
     * Process queued messages
     */
    function processQueue() {
        if (!isAuthenticated) {
            log('Not authenticated, skipping queue')
            return
        }
        while (messageQueue.length > 0 && socket && socket.readyState === WebSocket.OPEN) {
            var msg = messageQueue.shift()
            socket.send(msg)
            log('Sent queued message')
        }
    }

    /**
     * Send message through WebSocket
     */
    function sendMessage(message) {
        var jsonStr = JSON.stringify(message)
        
        if (socket && socket.readyState === WebSocket.OPEN && isAuthenticated) {
            socket.send(jsonStr)
            log('Sent message', message)
        } else {
            // Queue the message if not connected/authenticated
            messageQueue.push(jsonStr)
            log('Queued message (socket not ready or not authenticated)')
            
            // Try to connect
            initWebSocket()
        }
    }

    /**
     * Handle response from server
     */
    function handleResponse(pending, responseHtml) {
        var elt = pending.elt
        var target = pending.target
        var swapSpec = pending.swapSpec
        var resolve = pending.resolve
        var requestConfig = pending.requestConfig

        log('Handling response for', pending.path)

        // Create mock responseInfo for htmx events
        var responseInfo = {
            target: target,
            requestConfig: requestConfig,
            pathInfo: {
                requestPath: pending.path,
                finalRequestPath: pending.path,
                responsePath: null
            },
            xhr: {
                status: 200,
                response: responseHtml,
                getResponseHeader: function(name) { return null }
            }
        }

        // Trigger htmx:beforeOnLoad event
        if (!api.triggerEvent(elt, 'htmx:beforeOnLoad', responseInfo)) {
            resolve && resolve()
            return
        }

        // Apply transformations from extensions
        api.withExtensions(elt, function(extension) {
            if (extension.transformResponse) {
                responseHtml = extension.transformResponse(responseHtml, null, elt)
            }
        })

        // Get swap specification
        var swapStyle = swapSpec.swapStyle || 'innerHTML'
        
        // Use htmx's internal swap function
        api.swap(target, responseHtml, {
            swapStyle: swapStyle,
            swapDelay: swapSpec.swapDelay || 0,
            settleDelay: swapSpec.settleDelay || 0,
            ignoreTitle: swapSpec.ignoreTitle
        }, {
            contextElement: elt,
            eventInfo: responseInfo,
            afterSwapCallback: function() {
                api.triggerEvent(elt, 'htmx:afterSwap', responseInfo)
            },
            afterSettleCallback: function() {
                api.triggerEvent(elt, 'htmx:afterSettle', responseInfo)
            }
        })

        // Trigger afterRequest event
        api.triggerEvent(elt, 'htmx:afterRequest', responseInfo)

        resolve && resolve()
    }

    /**
     * Get swap specification from element
     */
    function getSwapSpec(elt) {
        var swapAttr = api.getAttributeValue(elt, 'hx-swap') || 'innerHTML'
        var parts = swapAttr.split(':')
        
        return {
            swapStyle: parts[0] || 'innerHTML',
            swapDelay: 0,
            settleDelay: 20,
            ignoreTitle: false
        }
    }

    // Register the extension
    htmx.defineExtension('vxui-ws', {

        /**
         * Initialize the extension
         */
        init: function(apiRef) {
            api = apiRef
            log('vxui-ws extension initialized')
            token = getToken()
            
            // Initialize WebSocket when DOM is ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', initWebSocket)
            } else {
                initWebSocket()
            }
        },

        /**
         * Handle events
         */
        onEvent: function(name, evt) {
            var elt = evt.target || evt.detail.elt

            switch (name) {
                // Initialize WebSocket before processing nodes
                case 'htmx:beforeProcessNode':
                    initWebSocket()
                    break

                // Intercept AJAX requests
                case 'htmx:beforeRequest':
                    var xhr = evt.detail.xhr
                    var requestConfig = evt.detail.requestConfig
                    
                    // Skip if not a real XHR (already handled)
                    if (!xhr) {
                        return true
                    }

                    log('Intercepting request to', requestConfig.path)

                    // Generate RPC ID
                    var rpcID = generateRpcID()

                    // Build message for vxui backend
                    var message = {
                        rpcID: rpcID,
                        verb: requestConfig.verb.toUpperCase(),
                        path: requestConfig.path,
                        body: paramsToObject(requestConfig.formData),
                        parameters: paramsToObject(requestConfig.formData),
                        headers: requestConfig.headers,
                        elt: requestConfig.elt ? requestConfig.elt.tagName : null,
                        timestamp: Date.now()
                    }
                    
                    // Add token if available
                    if (token) {
                        message.token = token
                    }

                    // Store pending request info
                    pendingRequests[rpcID] = {
                        elt: elt,
                        target: evt.detail.target,
                        swapSpec: getSwapSpec(elt),
                        path: requestConfig.path,
                        requestConfig: requestConfig,
                        resolve: null,
                        reject: null
                    }

                    // Send via WebSocket
                    sendMessage(message)

                    // Prevent default XHR
                    if (evt.preventDefault) {
                        evt.preventDefault()
                    }
                    return false

                // Cleanup on element removal
                case 'htmx:beforeCleanupElement':
                    break
            }

            return true
        },

        /**
         * Transform response (optional)
         */
        transformResponse: function(text, xhr, elt) {
            return text
        }
    })

    // Expose utility functions for debugging
    window.vxuiWs = {
        getSocket: function() { return socket },
        getPendingRequests: function() { return pendingRequests },
        getQueueLength: function() { return messageQueue.length },
        isAuthenticated: function() { return isAuthenticated },
        getClientId: function() { return clientId },
        reconnect: function() {
            if (socket) {
                socket.close()
            }
            initWebSocket()
        },
        setDebug: function(enabled) {
            config.debug = enabled
        },
        runJs: function(script) {
            return eval(script)
        }
    }

})()