#!/bin/bash

###############################################################################
# MAIN - Universal Device Interrogator & Controller
# ---------------------------------------------------------------------------
# Hardware: USB-Ethernet Adapter
# Features: Collision Bypass, Passive/Active Discovery, Wireshark Recording,
#           ONVIF Auto-Fetch, and Interactive Menu.
###############################################################################

# --- USER CONFIGURATION ---
TARGET_MAC="00:e0:4c:68:00:f5"
LOG_DIR="./device_logs"
MY_TEMP_IP="250"
VENV_PATH="./camera_env/bin/activate"
# --------------------------

# 1. AUTO-LOCATE INTERFACE BY MAC
INTERFACE=$(ip -br link | grep -i "$TARGET_MAC" | awk '{print $1}')

if [ -z "$INTERFACE" ]; then
    echo "ERROR: Adapter with MAC $TARGET_MAC not found."
    echo "Check connection or verify MAC in script."
    exit 1
fi

mkdir -p "$LOG_DIR"

# Detect home network to avoid routing collisions
HOME_INT=$(ip route | grep default | awk '{print $5}' | head -n 1)
HOME_SUB=$(ip -4 addr show "$HOME_INT" | grep -oP '(?<=inet\s)\d+(\.\d+){2}' | head -n 1)

# --- FUNCTIONS ---

setup_network() {
    echo -e "\n--- Initializing $INTERFACE ---"
    sudo ip link set "$INTERFACE" up
    sudo ip addr flush dev "$INTERFACE"

    echo "Listening for heartbeats (10s)..."
    DET_IP=$(sudo timeout 10s tcpdump -i "$INTERFACE" -n -c 1 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '0.0.0.0' | head -n 1)

    if [ -z "$DET_IP" ]; then
        echo "No traffic found. Trying active ARP scan..."
        DET_IP=$(sudo arp-scan --interface="$INTERFACE" --localnet | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi

    if [ -z "$DET_IP" ]; then
        echo "Device not found. Try power-cycling the camera."
        return 1
    fi

    DEV_SUB=$(echo "$DET_IP" | cut -d. -f1-3)
    sudo ip addr add "$DEV_SUB.$MY_TEMP_IP/24" dev "$INTERFACE"

    if [ "$DEV_SUB" == "$HOME_SUB" ]; then
        echo "Collision detected! Prioritizing USB path for $DET_IP."
        sudo ip route add "$DET_IP" dev "$INTERFACE" metric 10
    fi
    echo -e "\e[32mConnected to: $DET_IP\e[0m"
}

run_interrogation() {
    [ -z "$DET_IP" ] && { echo "Please Connect (Option 1) first."; return; }
    TS=$(date +%Y%m%d_%H%M%S)
    LOG="$LOG_DIR/details_$TS.log"
    PCAP="$LOG_DIR/capture_$TS.pcap"

    echo "Starting PCAP capture & Nmap scan..."
    sudo tcpdump -i "$INTERFACE" -w "$PCAP" & TCP_PID=$!

    MAC=$(ip neighbor show | grep "$DET_IP" | awk '{print $5}')
    MANU=$(grep -i "${MAC:0:8}" /usr/share/nmap/nmap-mac-prefixes | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}')

    {
        echo "=== DEVICE REPORT: $TS ==="
        echo "IP: $DET_IP | MAC: $MAC | Vendor: ${MANU:-Unknown}"
        echo "------------------------------------------------"
        sudo nmap -sV -O -F "$DET_IP"
    } | tee "$LOG"

    echo -e "\nInterrogation complete. Files saved to $LOG_DIR."
}

auto_fetch_rtsp() {
    [ -z "$DET_IP" ] && { echo "Connect first."; return; }
    if [ ! -f "$VENV_PATH" ]; then
        echo "Error: Python venv not found at $VENV_PATH."
        return
    fi

    echo "Testing credentials against ONVIF service..."
    while IFS=: read -r USER PASS; do
        echo -n "Trying $USER:$PASS ... "
        RESULT=$(source "$VENV_PATH" && python3 get_rtsp_path.py "$DET_IP" "$USER" "$PASS")

        if [[ $RESULT == *"SUCCESS_URL"* ]]; then
            URL=$(echo "$RESULT" | cut -d':' -f2-)
            echo -e "\e[32mFOUND!\e[0m"
            echo -e "\nURL: $URL\n"
            echo "RTSP_URL: $URL ($USER:$PASS)" >> "$LOG_DIR/details_$(date +%Y%m%d).log"
            return
        else
            echo "Failed."
        fi
    done < "camera_creds.txt"
}

cleanup() {
    echo "Cleaning up network and background processes..."
    [ ! -z "$TCP_PID" ] && sudo kill "$TCP_PID" 2>/dev/null
    sudo ip route del "$DET_IP" dev "$INTERFACE" 2>/dev/null
    sudo ip addr flush dev "$INTERFACE"
}

# --- MENU ---
while true; do
    echo -e "\n\e[1m--- CAMERA TOOLKIT MENU ---\e[0m"
    echo "1) Connect & Discover (Find IP)"
    echo "2) Interrogate & Capture (Log/PCAP)"
    echo "3) Auto-Fetch RTSP (via ONVIF)"
    echo "4) Brute-Force RTSP (Fallback Script)"
    echo "5) Cleanup / Reset Adapter"
    echo "6) Exit"
    read -p "Selection: " opt
    case $opt in
        1) setup_network ;;
        2) run_interrogation ;;
        3) auto_fetch_rtsp ;;
        4) [ -f ./rtsp_brute.sh ] && bash ./rtsp_brute.sh "$DET_IP" ;;
        5) cleanup ;;
        6) cleanup; exit ;;
        *) echo "Invalid option." ;;
    esac
done
