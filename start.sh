#!/bin/bash
# Bun Cha POS - Startup Script
# This script starts both the R Plumber API and Node.js Socket.IO relay

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "========================================="
echo "  Bun Cha POS - Starting Services"
echo "========================================="
echo ""

# Function to cleanup background processes
cleanup() {
    echo ""
    echo "Stopping services..."
    if [ ! -z "$R_PID" ]; then
        kill $R_PID 2>/dev/null
        echo "R Plumber API stopped"
    fi
    if [ ! -z "$NODE_PID" ]; then
        kill $NODE_PID 2>/dev/null
        echo "Node.js Socket.IO relay stopped"
    fi
    exit 0
}

# Trap SIGINT and SIGTERM
trap cleanup SIGINT SIGTERM

# Check if R is installed
if ! command -v R &> /dev/null; then
    echo "Error: R is not installed or not in PATH"
    echo "Please install R to run the Plumber API server"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed or not in PATH"
    echo "Please install Node.js to run the Socket.IO relay"
    exit 1
fi

# Check for R packages
echo "Checking R packages..."
R --quiet --no-save <<EOF
required_packages <- c("plumber", "openxlsx", "lubridate", "jsonlite", "httr")
missing_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]

if (length(missing_packages) > 0) {
    cat("Missing R packages:", paste(missing_packages, collapse=", "), "\n")
    cat("Please install them with:\n")
    cat("install.packages(c(", paste(paste0('"', missing_packages, '"'), collapse=", "), "))\n")
    quit(status=1)
} else {
    cat("All required R packages are installed\n")
}
EOF

if [ $? -ne 0 ]; then
    echo ""
    echo "To install missing R packages, run in R:"
    echo 'install.packages(c("plumber", "openxlsx", "lubridate", "jsonlite", "httr"))'
    exit 1
fi

echo ""

# Start R Plumber API server
echo "Starting R Plumber API (port 3003)..."
cd "$SCRIPT_DIR/R"
Rscript plumber.R &
R_PID=$!

# Wait a moment for R to start
sleep 2

# Check if R process is still running
if ! kill -0 $R_PID 2>/dev/null; then
    echo "Error: R Plumber API failed to start"
    exit 1
fi

echo "R Plumber API started (PID: $R_PID)"

# Start Node.js Socket.IO relay
echo ""
echo "Starting Node.js Socket.IO relay (port 3004)..."
cd "$SCRIPT_DIR/node_socket"
node socket_relay.js &
NODE_PID=$!

# Wait a moment for Node to start
sleep 1

# Check if Node process is still running
if ! kill -0 $NODE_PID 2>/dev/null; then
    echo "Error: Node.js Socket.IO relay failed to start"
    kill $R_PID 2>/dev/null
    exit 1
fi

echo "Node.js Socket.IO relay started (PID: $NODE_PID)"

echo ""
echo "========================================="
echo "  All services started successfully!"
echo "========================================="
echo ""
echo "  R Plumber API:    http://localhost:3003"
echo "  Socket.IO Relay:  http://localhost:3004"
echo "  Frontend:         http://localhost:3004/tables.html"
echo ""
echo "Press Ctrl+C to stop all services"
echo ""

# Wait for processes
wait $R_PID $NODE_PID
