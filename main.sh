#!/bin/bash

###############################################################################
# MAIN - Organized Device Interrogator
# ---------------------------------------------------------------------------
# Hierarchy: Manufacturer / Model / Camera_Name / {PCAP, MAC_FILE.txt}
###############################################################################

# --- USER CONFIGURATION ---
TARGET_MAC="00:e0:4c:68:00:f5"
BASE_LOG_DIR="./device_logs"
MY_TEMP_IP="250"
VENV_PATH="./camera_env/bin/activate"
# --------------------------

# 1. AUTO-LOCATE INTERFACE
INTERFACE=$(ip -br link | grep -i "$TARGET_MAC" | awk '{print $1}')
[ -z "$INTERFACE" ] && { echo "Error: Adapter not found."; exit 1; }

mkdir -p "$BASE_LOG_DIR"
HOME_INT=$(ip route | grep default | awk '{print $5}' | head -n 1)
HOME_SUB=$(ip -4 addr show "$HOME_INT" | grep -oP '(?<=inet\s)\d+(\.\d+){2}' | head -n 1)

# --- FUNCTIONS ---

setup_network() {
    echo -e "\n--- Initializing $INTERFACE ---"
    sudo ip link set "$INTERFACE" up
    sudo ip addr flush dev "$INTERFACE"

    echo "Listening for valid host traffic (15s)..."
    DET_IP=$(sudo timeout 15s tcpdump -i "$INTERFACE" -n -c 1 "not multicast and not broadcast" 2>/dev/null | \
             grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
             grep -vE '0.0.0.0|224\.|239\.|255\.' | head -n 1)

    if [ -z "$DET_IP" ]; then
        echo "No valid traffic caught."
        # Use user-configured or input IP for probing
        PROBE_IP_BASE="192.168.1"
        PROBE_IP="${PROBE_IP_BASE}.${MY_TEMP_IP}"

        read -p "Enter Probe IP to use for active scan (Default: $PROBE_IP): " USER_PROBE_IP
        if [ ! -z "$USER_PROBE_IP" ]; then
             PROBE_IP="$USER_PROBE_IP"
        fi

        # Check if the IP is already in use on the local network (if applicable) before assigning
        if ping -c 1 -W 1 "$PROBE_IP" &> /dev/null; then
             echo "WARNING: IP $PROBE_IP appears to be in use! Aborting scan to avoid conflict."
             return 1
        fi

        echo "Assigning probe IP $PROBE_IP/24 and scanning..."
        sudo ip addr add "$PROBE_IP/24" dev "$INTERFACE"

        # Scan common subnets
        DET_IP=$(sudo arp-scan --interface="$INTERFACE" 192.168.1.0/24 192.168.0.0/24 10.0.0.0/24 2>/dev/null | \
                 grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
                 grep -v "$PROBE_IP" | head -n 1)
    fi

    if [ -z "$DET_IP" ]; then
        echo "FAIL: Device not found."
        sudo ip addr flush dev "$INTERFACE"
        return 1
    fi

    sudo ip addr flush dev "$INTERFACE"
    DEV_SUB=$(echo "$DET_IP" | cut -d. -f1-3)

    # Check for conflict with target device IP before assigning our own address in that subnet
    MY_ADDR="$DEV_SUB.$MY_TEMP_IP"
    if ping -c 1 -W 1 "$MY_ADDR" &> /dev/null; then
         echo "WARNING: $MY_ADDR is in use. Please select a different host suffix."
         read -p "Enter new host suffix (e.g. 251): " NEW_SUFFIX
         MY_ADDR="$DEV_SUB.$NEW_SUFFIX"
    fi

    sudo ip addr add "$MY_ADDR/24" dev "$INTERFACE"
    [ "$DEV_SUB" == "$HOME_SUB" ] && sudo ip route add "$DET_IP" dev "$INTERFACE" metric 10

    echo -e "\e[32mCONNECTED TO: $DET_IP\e[0m"
}

run_interrogation() {
    [ -z "$DET_IP" ] && { echo "Connect first."; return; }

    # Identify MAC and Manufacturer
    MAC=$(ip neighbor show | grep "$DET_IP" | awk '{print $5}')
    [ -z "$MAC" ] && MAC=$(sudo arp-scan --interface="$INTERFACE" "$DET_IP" | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}')

    RAW_MANU=$(grep -i "${MAC:0:8}" /usr/share/nmap/nmap-mac-prefixes | awk '{$1=""; print $0}' | sed 's/^ //g')
    MANU=${RAW_MANU:-"Unknown_Manufacturer"}
    MANU_PATH=$(echo "$MANU" | tr ' ' '_')

    # Get User Details
    echo -e "\n--- Organization Details ---"
    read -p "Enter Camera Model: " CAM_MODEL
    CAM_MODEL=${CAM_MODEL:-"Generic_Model"}
    read -p "Enter Camera Name: " CAM_NAME
    CAM_NAME=${CAM_NAME:-"Unnamed_Cam"}

    # Finalize Directory and File paths
    FINAL_DIR="$BASE_LOG_DIR/$MANU_PATH/$CAM_MODEL/$CAM_NAME"
    MAC_FILE="$FINAL_DIR/${MAC//:/}.txt"
    TS=$(date +%Y%m%d_%H%M%S)
    PCAP="$FINAL_DIR/capture_$TS.pcap"

    mkdir -p "$FINAL_DIR"
    echo "Saving data to $FINAL_DIR"

    # Start Wireshark-compatible capture
    sudo tcpdump -i "$INTERFACE" -w "$PCAP" & TCP_PID=$!

    {
        echo "=== DEVICE INTERROGATION REPORT ==="
        echo "Timestamp:    $(date)"
        echo "Camera Name:  $CAM_NAME"
        echo "Model:        $CAM_MODEL"
        echo "IP:           $DET_IP"
        echo "MAC:          $MAC"
        echo "Vendor:       $MANU"
        echo "------------------------------------------------"
        sudo nmap -sV -O -F "$DET_IP"
    } | tee "$MAC_FILE"
}

auto_fetch_rtsp() {
    if [[ -z "$FINAL_DIR" || -z "$MAC_FILE" ]]; then
        echo "Run Interrogation (Option 2) first to define the camera folder."
        return
    fi

    echo "Checking ONVIF for RTSP path..."
    while IFS=: read -r USER PASS; do
        echo -n "Trying $USER:$PASS ... "
        RESULT=$(source "$VENV_PATH" && python3 get_rtsp_path.py "$DET_IP" "$USER" "$PASS" 2>/dev/null)

        if [[ $RESULT == *"SUCCESS_URL"* ]]; then
            URL=$(echo "$RESULT" | cut -d':' -f2-)
            echo -e "\e[32mFOUND!\e[0m"
            echo -e "\nVerified RTSP URL ($USER:$PASS):\n$URL" >> "$MAC_FILE"
            return
        else
            echo "Failed."
        fi
    done < "camera_creds.txt"
}

cleanup() {
    echo "Resetting adapter..."
    [ ! -z "$TCP_PID" ] && sudo kill "$TCP_PID" 2>/dev/null
    sudo ip route del "$DET_IP" dev "$INTERFACE" 2>/dev/null
    sudo ip addr flush dev "$INTERFACE"
}

# --- MENU ---
while true; do
    echo -e "\n--- CAMERA TOOLKIT ---"
    echo "1) Connect & Discover (Find IP)"
    echo "2) Interrogate & Capture (Setup Folders/Nmap/PCAP)"
    echo "3) Auto-Fetch RTSP (via ONVIF)"
    echo "4) Brute-Force RTSP (Fallback Script)"
    echo "5) Reset Adapter / Cleanup"
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
