var mainChart = null;
var previousHashrate = null;

function created() {
	mainChart = echarts.init(document.getElementById('chart'));
	mainChart.setOption(chartOption);

	// Listen for htmx afterSwap event to handle chart data
	document.body.addEventListener('htmx:afterSwap', function(evt) {
		var target = evt.detail.target;
		if (target && target.id === 'data') {
			var responseText = target.textContent || target.innerText;
			if (responseText) {
				try {
					var it = JSON.parse(responseText);
					if (it.get === 'hashtable') {
						renderChart(mainChart, it.dat.time_axis, {
							"key": it.dat.key,
							"values": it.dat.values
						});
						updateStats(it.dat.values);
					}
				} catch (e) {
					console.error('Failed to parse chart data:', e);
				}
			}
		}
	});
	
	// Resize chart on window resize
	window.addEventListener('resize', function() {
		if (mainChart) {
			mainChart.resize();
		}
	});
}

var chartOption = {
	backgroundColor: 'transparent',
	title: {
		show: false
	},
	legend: {
		show: false
	},
	grid: {
		top: 20,
		left: 10,
		right: 20,
		bottom: 40,
		containLabel: true
	},
	tooltip: {
		trigger: 'axis',
		backgroundColor: 'rgba(26, 26, 46, 0.95)',
		borderColor: 'rgba(58, 123, 213, 0.5)',
		borderWidth: 1,
		padding: [12, 16],
		textStyle: {
			color: '#e2e8f0',
			fontSize: 13
		},
		extraCssText: 'box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3); border-radius: 8px;'
	},
	xAxis: {
		type: 'time',
		axisLine: {
			lineStyle: {
				color: 'rgba(255, 255, 255, 0.1)'
			}
		},
		axisLabel: {
			color: '#8892b0',
			fontSize: 11,
			formatter: function (val) {
				return moment(new Date(parseInt(val, 10))).format('HH:mm');
			},
			showMaxLabel: false
		},
		splitLine: {
			show: true,
			lineStyle: {
				color: 'rgba(255, 255, 255, 0.05)'
			}
		},
	},
	yAxis: {
		type: 'value',
		axisLine: {
			show: false
		},
		axisLabel: {
			color: '#8892b0',
			fontSize: 11,
			showMaxLabel: false,
			formatter: function(val) {
				return val.toFixed(0);
			}
		},
		splitLine: {
			lineStyle: {
				color: 'rgba(255, 255, 255, 0.05)'
			}
		},
		max: 'dataMax'
	},
	series: [{
		type: 'line',
		showSymbol: false,
		smooth: 0.4,
		lineStyle: {
			width: 2,
			color: {
				type: 'linear',
				x: 0, y: 0, x2: 1, y2: 0,
				colorStops: [
					{ offset: 0, color: '#00d2ff' },
					{ offset: 0.5, color: '#3a7bd5' },
					{ offset: 1, color: '#00d2ff' }
				]
			},
			shadowColor: 'rgba(58, 123, 213, 0.5)',
			shadowBlur: 10,
			shadowOffsetY: 5
		},
		itemStyle: {
			color: '#3a7bd5'
		},
		areaStyle: {
			color: {
				type: 'linear',
				x: 0, y: 0, x2: 0, y2: 1,
				colorStops: [
					{ offset: 0, color: 'rgba(58, 123, 213, 0.4)' },
					{ offset: 0.5, color: 'rgba(58, 123, 213, 0.1)' },
					{ offset: 1, color: 'rgba(58, 123, 213, 0)' }
				]
			}
		},
		animationDuration: 500,
		animationEasing: 'cubicOut'
	}]
};

function updateStats(values) {
	if (!values || values.length === 0) return;
	
	var hashrates = values.map(v => v[1]);
	var current = hashrates[hashrates.length - 1];
	var avg = hashrates.reduce((a, b) => a + b, 0) / hashrates.length;
	var max = Math.max(...hashrates);
	var min = Math.min(...hashrates);
	
	// Update current hashrate
	document.getElementById('current-hashrate').textContent = current.toFixed(2) + ' MH/s';
	
	// Update change indicator
	if (previousHashrate !== null) {
		var change = ((current - previousHashrate) / previousHashrate * 100).toFixed(1);
		var changeEl = document.getElementById('hashrate-change');
		if (change >= 0) {
			changeEl.className = 'change up';
			changeEl.textContent = '↑ ' + change + '% from last';
		} else {
			changeEl.className = 'change down';
			changeEl.textContent = '↓ ' + Math.abs(change) + '% from last';
		}
	} else {
		document.getElementById('hashrate-change').textContent = 'First reading';
	}
	previousHashrate = current;
	
	// Update average
	document.getElementById('avg-hashrate').textContent = avg.toFixed(2) + ' MH/s';
	
	// Update max
	document.getElementById('max-hashrate').textContent = max.toFixed(2) + ' MH/s';
	
	// Update data points count
	document.getElementById('data-points').textContent = values.length;
}

function renderChart(chart, tickValues, hashrateHistory) {
	chart.setOption({
		tooltip: {
			formatter: function (params) {
				if (!params || params.length === 0) return '';
				params = params[0];
				var date = moment(new Date(parseInt(params.value[0], 10))).format('YYYY/MM/DD HH:mm:ss');
				var value = params.value[1].toFixed(2);
				return '<div style="font-weight: 600; margin-bottom: 4px;">' + date + '</div>' +
					   '<div style="color: #60a5fa;">' + hashrateHistory.key + ': <strong>' + value + '</strong> MH/s</div>';
			}
		},
		xAxis: {
			min: tickValues[0],
			interval: 3600 * 2 * 1000,
			axisLabel: {
				rotate: window.matchMedia && window.matchMedia('(max-width: 768px)').matches ? 30 : 0
			}
		},
		series: [{
			name: hashrateHistory.key,
			data: hashrateHistory.values
		}]
	});
}

created();
