var vxui_ws;
// Get the port number from the url parameter
const url = location.search; //get url string
let theRequest = new Object();
if (url.indexOf("?") != -1) {
	let str = url.substr(1);
	strs = str.split("&");
	for(let i = 0; i < strs.length; i++) {
		theRequest[strs[i].split("=")[0]]=unescape(strs[i].split("=")[1]);
	};
};

let vxui_ws_port = theRequest['vxui_ws_port'];

var wssSource = "ws://localhost:" + vxui_ws_port + "/echo";
var sock = new WebSocket(wssSource, []);

var handlers={}; // saved ajax handlers: key=id, val=handler
var configs={};

sock.onmessage = function(e) {
	if (e.data != "pong") {
		console.log(e);
		var resp=JSON.parse(e.data);		// Convert the JSON response to an object
		var handler=handlers[resp.rpcID];	// Find the handler
		var config=configs[resp.rpcID];		// Find the config
		delete handlers[resp.rpcID];		// Release
		delete configs[resp.rpcID];			// Release
		handler.resolve({
			config: config,
			status: 200,
			headers: {'content-type': 'text/text'},
			response: resp.data,
		});
	};
};

// Generate a unique RPC ID using timestamp + random + counter
let rpcCounter = 0;
function generateRpcID() {
	const timestamp = Date.now().toString(36);
	const random = Math.random().toString(36).substring(2, 8);
	const counter = (rpcCounter++).toString(36);
	return `${timestamp}-${random}-${counter}`;
}

ah.proxy({
	// Before send request, replace it with websocket request
	onRequest: (config, handler) => {
		var toSend = {};

		// Generate a unique RPC ID
		var rpcID = generateRpcID();

		// Handle collision (extremely unlikely but possible)
		while(handlers[rpcID]) {
			rpcID = generateRpcID();
		}

		handlers[rpcID] = handler;	// Save handler, where rpcID is the key.
		configs[rpcID] = config;

		toSend['rpcID'] = rpcID;
		toSend['body'] = createObjFromPairedArrayValues(decodeURI(config.body).split('&'));
		toSend['verb'] = config.method;
		toSend['path'] = config.url;
		toSend['headers'] = config.headers;
		toSend['timestamp'] = Date.now(); // Add timestamp for debugging

		sock.send(JSON.stringify(toSend));
	}
});

/*
 * @Author
 * Micaiah Effiong
 * https://github.com/micaiah-effiong/queryToJson
 * 
*/

/*
	* @param {String} query 
	* @param {Boolean} option specifies if ${query} should be a valid URL 
	*
	* return Object
	*
	* example: queryToJson('query=name', true)
	* // this is not valid
	* Invalid URL
	*
	* example: queryToJson('query=name', false)
	* // this is valid
	* {'query': 'name'}
	*
*/
function queryToJson(query, option=true){
	if(!query){
		throw TypeError('1 argument required, but only 0 present.');
	}
	let _string 

	try{
		_string = new URL(query).search.substring(1)
		console.log(_string);
	}catch(err){
		if (option == true){
			throw err;
		}
		console.log("catch");
		_string = (query.substring(query.indexOf('?')+1))
		? query.substring(1)
		: query;
		console.log(query);
	}

	return createObjFromPairedArrayValues(_string.split('&'));
}

/*
 * @param {Array} _arr ["foo=bar"]
 * return {Object} obj {foo: bar}
 *
*/
function createObjFromPairedArrayValues(_arr){
	let obj = Object.create(null);
	_arr.forEach(function(elt){
		let pair = elt.split('=');
		pair[1] = decodeURIComponent(pair[1]).replace(/\+/g, " ");
		if (obj[pair[0]] && typeof obj[pair[0]] == 'string') {
			let placeholder = obj[pair[0]];
			obj[pair[0]] = new Array();
			obj[pair[0]].push(placeholder, pair[1]);
		}else	if (obj[pair[0]] && obj[pair[0]] instanceof Array == true) {
			obj[pair[0]].push(pair[1]);
		}else{
			obj[pair[0]] = pair[1];
		}
	});
	return obj;
}
