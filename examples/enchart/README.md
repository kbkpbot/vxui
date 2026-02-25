# Real-time Charts Demo

A dashboard application demonstrating real-time data visualization with ECharts integration.

## Features

- **Real-time Data**: Random data generation every second
- **ECharts Integration**: Professional chart rendering
- **Live Statistics**: Current, average, and peak value tracking
- **Dark Theme**: Modern dashboard UI with dark theme
- **Hashrate Visualization**: Example of time-series data display

## How to Run

```sh
# From this directory
v run main.v
```

Or build and run:

```sh
v -prod -o enchart main.v
./enchart
```

## What It Demonstrates

This example shows how to:
- Send JSON data from V backend to frontend
- Integrate with third-party charting libraries (ECharts)
- Implement real-time data streaming
- Use JavaScript to process backend data
- Create dashboard-style applications

## Architecture

1. Frontend uses ECharts for visualization
2. Backend generates random data every second
3. Data is sent as JSON and rendered in real-time
4. Statistics are calculated and displayed live
