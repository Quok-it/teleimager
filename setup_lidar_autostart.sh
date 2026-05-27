#!/bin/bash

# ==============================================================
# LiDAR Bridge Setup Script
# --------------------------------------------------------------
# Builds lidar_bridge inside the unitree_sdk2 example tree and
# registers it as a systemd service that starts on every boot.
#
# Requirements:
#   - unitree_sdk2 at /home/unitree/unitree_sdk2 (pre-installed on G1)
#   - libzmq-dev
#   - sudo privileges
#
# Usage:
#   bash setup_lidar_autostart.sh
#
# After setup:
#   sudo systemctl status lidar-bridge.service
#   sudo journalctl -u lidar-bridge.service -f
#   sudo systemctl restart lidar-bridge.service
#   sudo systemctl disable lidar-bridge.service
# ==============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_PATH="/home/unitree/unitree_sdk2"
BRIDGE_SRC="$SDK_PATH/example/lidar_bridge"
BUILD_DIR="$SDK_PATH/build"
BRIDGE_BIN="$BUILD_DIR/bin/lidar_bridge"
LIB_PATH="$SDK_PATH/thirdparty/lib/aarch64"

echo "=== LiDAR Bridge Setup ==="

# Check unitree_sdk2
if [ ! -d "$SDK_PATH" ]; then
    echo "Error: unitree_sdk2 not found at $SDK_PATH"
    echo "The unitree_sdk2 should be pre-installed on the G1 robot."
    exit 1
fi

# Install libzmq-dev if missing
if ! ldconfig -p | grep -q libzmq; then
    echo "Installing libzmq-dev..."
    sudo apt install -y libzmq-dev
fi

# --- Step 1: Copy source into sdk2 example tree ---
echo "Copying lidar_bridge source into unitree_sdk2 example tree..."
mkdir -p "$BRIDGE_SRC"
cp "$SCRIPT_DIR/lidar_bridge.cpp" "$BRIDGE_SRC/"

cat > "$BRIDGE_SRC/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.5)
project(lidar_bridge)
add_executable(lidar_bridge lidar_bridge.cpp)
target_link_libraries(lidar_bridge unitree_sdk2 zmq pthread)
EOF

# Add subdirectory to example CMakeLists.txt (idempotent)
EXAMPLE_CMAKE="$SDK_PATH/example/CMakeLists.txt"
if ! grep -q "add_subdirectory(lidar_bridge)" "$EXAMPLE_CMAKE"; then
    echo "add_subdirectory(lidar_bridge)" >> "$EXAMPLE_CMAKE"
fi

# --- Step 2: Build ---
echo "Building lidar_bridge..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake .. -DCMAKE_BUILD_TYPE=Release > /dev/null
make lidar_bridge -j4

echo "Built: $BRIDGE_BIN"

# --- Step 3: Detect network interface ---
DEFAULT_IFACE="eth0"
read -p "Network interface for LiDAR DDS (default: $DEFAULT_IFACE): " IFACE_INPUT
IFACE="${IFACE_INPUT:-$DEFAULT_IFACE}"
echo "Using interface: $IFACE"

# --- Step 4: Create systemd service ---
SERVICE_FILE="/etc/systemd/system/lidar-bridge.service"
echo "Creating $SERVICE_FILE..."
sudo tee "$SERVICE_FILE" > /dev/null << EOL
[Unit]
Description=Unitree LiDAR Bridge
After=network.target

[Service]
Type=simple
User=unitree
ExecStart=$BRIDGE_BIN $IFACE
Environment="LD_LIBRARY_PATH=$LIB_PATH"
Restart=always
RestartSec=5
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable lidar-bridge.service
sudo systemctl restart lidar-bridge.service

sleep 2
sudo systemctl status lidar-bridge.service --no-pager

echo ""
echo "=== LiDAR Bridge setup complete ==="
echo "ZMQ output: cloud on port 55560, range image on port 55561"
echo ""
echo "  sudo systemctl status lidar-bridge.service     # Check status"
echo "  sudo journalctl -u lidar-bridge.service -f     # Live logs"
echo "  sudo systemctl restart lidar-bridge.service    # Restart"
echo "  sudo systemctl disable lidar-bridge.service    # Disable auto-start"
