function created() {
	var i;
	var mainChart = echarts.init(document.getElementById('chart'));
	mainChart.setOption(chartOption);

	// Get the port number from the url parameter
	var vxui_ws;
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
	var ws = new WebSocket(wssSource, []);
	
	setInterval(function () {
		ws.send(JSON.stringify({
				path: '/get',
				verb: 'GET',
				rpcID: 0,
				data: 'hashtable'
			}));
		}, 1000);
	ws.onmessage = function (evt) {
		if (ws) {
			if (evt.data != 'pong') {
			var it = JSON.parse(JSON.parse(evt.data).data);
			if (it.get) {
				if (it.get === 'hashtable') {
					renderChart(mainChart, it.dat.time_axis, {
						"key": it.dat.key,
						"values": it.dat.values
					});
				}
			}
			}
		}
	};
}

var chartOption = {
	title: {
		text: "last 24 hour hashrate",
		textStyle: {
			color: '#34495e'
		},
		top: 0,
		right: 10
	},
	legend: {
		right: 10,
		top: 30,
		itemWidth: 12,
		itemHeight: 12,
		selectedMode: false,
	},
	grid: {
		top: 80,
		left: 0,
		right: 20,
		containLabel: true
	},
	tooltip: {
		trigger: 'axis',
		backgroundColor: 'rgba(255, 255, 255, 0.8)',
		borderColor: '#333',
		borderWidth: 1,
		padding: [5, 10],
		textStyle: {
			color: '#000',
			fontSize: 12
		}
	},
	xAxis: {
		type: 'time',
		axisLabel: {
			formatter: function (val) {
				return moment(new Date(parseInt(val, 10))).format('HH:mm');
			},
			showMaxLabel: false
		},
		splitLine: {
			show: true,
			lineStyle: {
				opacity: 0.4
			}
		},
	},
	yAxis: {
		type: 'value',
		splitLine: {
			lineStyle: {
				opacity: 0.4
			}
		},
		axisLabel: {
			showMaxLabel: false
		},
		max: 'dataMax'
	},
	series: [{
			type: 'line',
			showSymbol: false,
			smooth: true,
			lineStyle: {
				normal: {
					color: '#2b90e9',
					width: 1
				}
			},
			itemStyle: {
				normal: {
					color: '#88d0f8',
					borderColor: '#2b90e9'
				},
				emphasis: {
					color: '#2b90e9'
				}
			},
			areaStyle: {
				normal: {
					color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [{
								offset: 0,
								color: '#b5ecff'
							}, {
								offset: 1,
								color: '#d1fbff'
							}
						]),
					opacity: 0.5
				}
			}
		}
	]
};

function renderChart(chart, tickValues, hashrateHistory) {
	chart.setOption(chartOption);
	chart.setOption({
		legend: {
			data: [{
					name: hashrateHistory.key,
					icon: 'circle'
				}
			]
		},
		tooltip: {
			formatter: function (params) {
				params = params[0];
				return '<strong>' +
				moment(new Date(parseInt(params.value[0], 10))).format('YYYY/MM/DD HH:mm') +
				'</strong><br>' + hashrateHistory.key + ': <strong>' +
				params.value[1] + '</strong> ';
			}
		},
		xAxis: {
			min: tickValues[0],
			interval: 3600 * 2 * 1000,
			axisLabel: {
				rotate: window.matchMedia && window.matchMedia('(max-width: 500px)').matches ? 40 : 0
			}
		},
		series: [{
				name: hashrateHistory.key,
				data: hashrateHistory.values
			}
		]
	});
}

created();