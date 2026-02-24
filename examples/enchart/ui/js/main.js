var mainChart = null;

function created() {
	mainChart = echarts.init(document.getElementById('chart'));
	mainChart.setOption(chartOption);

	// Listen for htmx afterRequest event to handle chart data
	document.body.addEventListener('htmx:afterRequest', function(evt) {
		if (evt.detail.pathInfo.requestPath === '/get') {
			var xhr = evt.detail.xhr;
			if (xhr && xhr.response) {
				try {
					var it = JSON.parse(xhr.response);
					if (it.get === 'hashtable') {
						renderChart(mainChart, it.dat.time_axis, {
							"key": it.dat.key,
							"values": it.dat.values
						});
					}
				} catch (e) {
					console.error('Failed to parse chart data:', e);
				}
			}
		}
	});
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