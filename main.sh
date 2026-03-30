#!/bin/bash

###############################################################################
# MAIN - Universal Device Interrogator (Validated Subnet Edition)
###############################################################################

# --- USER CONFIGURATION ---
TARGET_MAC="00:e0:4c:68:00:f5"
BASE_LOG_DIR="./device_logs"
MY_TEMP_IP="250"
VENV_PATH="./camera_env/bin/activate"
# --------------------------

# Global State
DET_IP=""
FINAL_DIR=""
MAC_FILE=""
TCP_PID=""
TCP_RAW_PID=""

# 1. AUTO-LOCATE INTERFACE
INTERFACE=$(ip -br link | grep -i "$TARGET_MAC" | awk '{print $1}')
if [ -z "$INTERFACE" ]; then
    echo "ERROR: Adapter with MAC $TARGET_MAC not found."
    exit 1
fi

mkdir -p "$BASE_LOG_DIR"

cleanup() {
    trap - EXIT INT
    echo -e "\nResetting adapter and terminating background processes..."
    [ -n "$TCP_PID" ] && sudo kill "$TCP_PID" 2>/dev/null
    [ -n "$TCP_RAW_PID" ] && sudo kill "$TCP_RAW_PID" 2>/dev/null
    sudo pkill -f "dnsmasq.*camera_dhcp" 2>/dev/null
    rm -f /tmp/dnsmasq_camera.pid /tmp/camera_dhcp.leases /tmp/camera_raw.txt 2>/dev/null
    sudo ip addr flush dev "$INTERFACE" 2>/dev/null
    sudo nmcli device set "$INTERFACE" managed yes 2>/dev/null
    echo "Adapter reset complete."
}
trap cleanup EXIT INT

# --- CORE FUNCTIONS ---

# Function to check if a proposed IP/Subnet is safe to use
verify_safe_ip() {
    local PROPOSED_IP="$1" # e.g., 10.254.254.1 or 192.168.1.250
    local SUBNET_CIDR="$2" # e.g., 24

    # Check if this IP is pingable on other interfaces
    if ping -c 1 -W 1 "$PROPOSED_IP" > /dev/null 2>&1; then
        echo -e "\e[31mWARNING: Proposed IP $PROPOSED_IP is already responsive on the network!\e[0m"
        read -p "Do you want to use it anyway? (y/N): " FORCE_USE
        if [[ ! "$FORCE_USE" =~ ^[Yy]$ ]]; then
            return 1 # Unsafe
        fi
    fi

    # Check routing table to see if the subnet overlaps with an existing route (excluding our own interface)
    local BASE_IP=$(echo "$PROPOSED_IP" | cut -d. -f1-3)
    local OVERLAP=$(ip route show | grep -v "dev $INTERFACE" | grep -E "^$BASE_IP\.")

    if [ -n "$OVERLAP" ]; then
         echo -e "\e[31mWARNING: The subnet for $PROPOSED_IP conflicts with an existing network route:\e[0m"
         echo "  $OVERLAP"
         read -p "Do you want to proceed and assign this IP? (y/N): " FORCE_USE
         if [[ ! "$FORCE_USE" =~ ^[Yy]$ ]]; then
             return 1 # Unsafe
         fi
    fi

    return 0 # Safe to proceed
}


finalize_route() {
    if [ -z "$DET_IP" ]; then return; fi
    echo "Finalizing route for $DET_IP..."
    sudo ip addr flush dev "$INTERFACE"
    DEV_SUB=$(echo "$DET_IP" | cut -d. -f1-3)

    local PROPOSED_IP="$DEV_SUB.$MY_TEMP_IP"
    if ! verify_safe_ip "$PROPOSED_IP" "24"; then
        read -p "Enter a new host suffix (e.g. 251): " NEW_SUFFIX
        PROPOSED_IP="$DEV_SUB.${NEW_SUFFIX:-$MY_TEMP_IP}"
    fi

    # Set host IP and broadcast properly
    sudo ip addr add "$PROPOSED_IP/24" brd + dev "$INTERFACE"
    sudo ip link set "$INTERFACE" up
    sleep 2

    # Prime the ARP table one last time
    sudo arping -c 2 -I "$INTERFACE" "$DET_IP" > /dev/null 2>&1
    sudo ip route add "$DET_IP" dev "$INTERFACE" scope link 2>/dev/null
    echo -e "\e[32mSUCCESS: Tools 3 & 4 now targeting $DET_IP\e[0m"
}

listen_universal() {
    echo -e "\n--- Smart Multi-Stage Camera Trap (90s Capture Window) ---"
    sudo nmcli device set "$INTERFACE" managed no 2>/dev/null
    sudo ip link set "$INTERFACE" up
    sudo ip addr flush dev "$INTERFACE"

    local TRAP_IP="10.254.254.1"
    if ! verify_safe_ip "$TRAP_IP" "24"; then
        read -p "Enter a different trap IP (e.g., 10.123.123.1): " NEW_TRAP_IP
        TRAP_IP=${NEW_TRAP_IP:-"10.254.254.1"}
    fi

    local TRAP_SUBNET=$(echo "$TRAP_IP" | cut -d. -f1-3)
    sudo ip addr add "$TRAP_IP/24" dev "$INTERFACE"

    LEASE_FILE="/tmp/camera_dhcp.leases"
    RAW_FILE="/tmp/camera_raw.txt"
    > "$LEASE_FILE"
    > "$RAW_FILE"

    sudo dnsmasq --interface="$INTERFACE" --bind-interfaces --port=0 \
        --dhcp-range="$TRAP_SUBNET.10,$TRAP_SUBNET.50,12h" \
        --dhcp-leasefile="$LEASE_FILE" --pid-file="/tmp/dnsmasq_camera.pid" 2>/dev/null

    sudo tcpdump -i "$INTERFACE" -nn -l "ip and not host $TRAP_IP and not host 0.0.0.0 and not (dst net 224.0.0.0/4)" > "$RAW_FILE" 2>/dev/null & TCP_RAW_PID=$!

    echo -e "\e[33m[1/3] HARVESTING PHASE: Capturing all traffic for 90 seconds...\e[0m"
    echo "Power cycle the camera NOW."

    CAPTURE_END=$((SECONDS + 90))
    declare -A FOUND_IPS

    while [ $SECONDS -lt $CAPTURE_END ]; do
        REMAINING=$((CAPTURE_END - SECONDS))
        [ -s "$LEASE_FILE" ] && { for ip in $(awk '{print $3}' "$LEASE_FILE"); do FOUND_IPS["$ip"]=1; done; }
        [ -s "$RAW_FILE" ] && { for ip in $(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$RAW_FILE" | grep -vE "^0\.0\.0\.0$|^$TRAP_IP$|^255\.255\.255\.255$|^224\.|^239\.|.*\.250$"); do FOUND_IPS["$ip"]=1; done; }
        echo -ne "Time Left: ${REMAINING}s | Unique IPs found: ${#FOUND_IPS[@]} \r"
        sleep 2
    done
    echo -e "\nHarvesting complete."

    sudo pkill -f "dnsmasq.*camera_dhcp" 2>/dev/null
    sudo kill "$TCP_RAW_PID" 2>/dev/null

    # [2/3] VALIDATION PHASE - FIXED SUBNET SWITCHING
    echo -e "\e[33m[2/3] VALIDATION PHASE: Verifying addresses with subnet matching...\e[0m"
    VALID_IPS=()
    for ip in "${!FOUND_IPS[@]}"; do
        echo -n "Switching subnets to check $ip ... "
        sudo ip addr flush dev "$INTERFACE"
        TMP_SUB=$(echo "$ip" | cut -d. -f1-3)

        local VALIDATION_IP="$TMP_SUB.$MY_TEMP_IP"
        if ! verify_safe_ip "$VALIDATION_IP" "24"; then
            echo -e "\n\e[33mSkipping $ip check due to subnet conflict.\e[0m"
            continue
        fi

        # Set our adapter to match the subnet of the found IP
        sudo ip addr add "$VALIDATION_IP/24" dev "$INTERFACE"
        sudo ip link set "$INTERFACE" up
        sleep 1

        # arping is better than ping for this; it doesn't care about firewalls as much
        if sudo arping -c 2 -w 1 -I "$INTERFACE" "$ip" > /dev/null 2>&1; then
            echo -e "\e[32mALIVE\e[0m"
            VALID_IPS+=("$ip")
        else
            echo -e "\e[31mDEAD\e[0m"
        fi
    done

    # [3/3] SELECTION PHASE
    NUM_VALID=${#VALID_IPS[@]}
    if [ "$NUM_VALID" -eq 0 ]; then
        echo -e "\e[31mERROR: No IP addresses survived. The camera may have changed subnets again.\e[0m"
        DET_IP=""
    elif [ "$NUM_VALID" -eq 1 ]; then
        DET_IP="${VALID_IPS[0]}"
        echo -e "\e[32mAuto-selected permanent IP: $DET_IP\e[0m"
        finalize_route
    else
        echo -e "\n\e[36mMultiple active IPs found. Pick the permanent one:\e[0m"
        for i in "${!VALID_IPS[@]}"; do echo "$((i+1))) ${VALID_IPS[$i]}"; done
        read -p "Selection: " CHOICE
        DET_IP="${VALID_IPS[$((CHOICE-1))]}"
        finalize_route
    fi
}

run_interrogation() {
    if [ -z "$DET_IP" ]; then echo -e "\e[31mERROR: No IP detected yet.\e[0m"; return; fi
    echo "Analyzing $DET_IP..."
    MAC=$(sudo arp-scan --interface="$INTERFACE" "$DET_IP" | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1)

    # Vendor Lookup
    if [ -z "$MAC" ]; then
        MAC_STR=$(echo "$DET_IP" | tr '.' '_'); MANU="Unknown"
    else
        RAW_MANU=$(grep -i "${MAC:0:8}" /usr/share/nmap/nmap-mac-prefixes 2>/dev/null | awk '{$1=""; print $0}' | sed 's/^ //g')
        MANU=${RAW_MANU:-"Unknown"}; MAC_STR=$(echo "$MAC" | tr -d ':')
    fi

    echo -e "\n--- Organization Details ---"
    read -p "Enter Camera Model: " CAM_MODEL
    read -p "Enter Camera Name: " CAM_NAME
    CAM_MODEL=${CAM_MODEL:-"Generic"}; CAM_NAME=${CAM_NAME:-"Unnamed"}

    FINAL_DIR="$BASE_LOG_DIR/$(echo "$MANU" | tr ' ' '_')/$CAM_MODEL/$CAM_NAME"
    mkdir -p "$FINAL_DIR"; MAC_FILE="$FINAL_DIR/${MAC_STR}.txt"
    PCAP="$FINAL_DIR/capture_$(date +%H%M%S).pcap"

    # Kill any existing tcpdump session for interrogation to prevent zombies
    if [ -n "$TCP_PID" ]; then
        sudo kill "$TCP_PID" 2>/dev/null
        TCP_PID=""
    fi

    sudo tcpdump -i "$INTERFACE" -w "$PCAP" > /dev/null 2>&1 & TCP_PID=$!
    {
        echo "=== INTERROGATION REPORT ==="
        echo "IP: $DET_IP | MAC: ${MAC:-"N/A"} | Vendor: $MANU"
        echo "--------------------------------------"
        sudo nmap -sV -O -Pn -T4 "$DET_IP" -e "$INTERFACE"
    } | tee "$MAC_FILE"

    # Stop tcpdump capture when nmap is done
    if [ -n "$TCP_PID" ]; then
        echo "Stopping packet capture..."
        sudo kill "$TCP_PID" 2>/dev/null
        TCP_PID=""
    fi
}

setup_network() {
    local CUSTOM_RANGE=$1
    sudo nmcli device set "$INTERFACE" managed no 2>/dev/null
    sudo ip link set "$INTERFACE" up
    sudo ip addr flush dev "$INTERFACE"

    local RANGE_LIST=${CUSTOM_RANGE:-"192.168.1.0/24 192.168.0.0/24 10.0.0.0/24"}

    for RANGE in $RANGE_LIST; do
        SUBNET_PREFIX=$(echo "$RANGE" | cut -d. -f1-3)
        local PROPOSED_IP="$SUBNET_PREFIX.$MY_TEMP_IP"

        echo -e "\nChecking subnet $RANGE..."
        if ! verify_safe_ip "$PROPOSED_IP" "24"; then
            echo -e "\e[33mSkipping subnet $RANGE due to conflict or user abort.\e[0m"
            continue
        fi

        sudo ip addr add "$PROPOSED_IP/24" dev "$INTERFACE"
        echo "Scanning: $RANGE"
        sudo nmap -sn "$RANGE" -e "$INTERFACE" > /dev/null 2>&1

        # arp-scan requires just the network definition
        DET_IP=$(sudo arp-scan --interface="$INTERFACE" "$RANGE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -vE "$PROPOSED_IP" | head -n 1)

        if [ -n "$DET_IP" ]; then
            echo -e "\e[32mDevice found at $DET_IP on subnet $RANGE\e[0m"
            finalize_route
            return
        else
            echo "No device found on $RANGE."
            sudo ip addr flush dev "$INTERFACE"
        fi
    done

    echo "Scan complete. No devices found on any provided subnets."
    DET_IP=""
}

auto_fetch_rtsp() {
    if [[ -z "$FINAL_DIR" || -z "$MAC_FILE" ]]; then echo "Run Option 3 first."; return; fi
    while IFS=: read -r USER PASS; do
        [[ -z "$USER" || "$USER" == \#* ]] && continue
        echo -n "Trying $USER:$PASS ... "
        RESULT=$(source "$VENV_PATH" && python3 get_rtsp_path.py "$DET_IP" "$USER" "$PASS" 2>/dev/null)
        if [[ $RESULT == *"SUCCESS_URL"* ]]; then
            echo -e "\e[32mFOUND!\e[0m"
            echo -e "\nVerified RTSP URL ($USER:$PASS):\n$(echo "$RESULT" | cut -d':' -f2-)" >> "$MAC_FILE"
            return
        fi
        echo "Failed."
    done < "camera_creds.txt"
}

# --- MENU LOOP ---
while true; do
    echo -e "\n\e[1m--- CAMERA TOOLKIT MENU ---\e[0m"
    echo -e "Current Target: \e[36m${DET_IP:-"NONE"}\e[0m"
    echo "1) Active Ping Discovery"
    echo "2) Universal Boot Trap (Smart Validation)"
    echo "3) Interrogate & Capture"
    echo "4) Auto-Fetch RTSP"
    echo "5) Reset / Clear Target"
    echo "6) Exit"
    read -p "Selection: " opt
    case $opt in
        1) read -p "Enter Subnet (CIDR) or [Enter]: " S_RANGE; setup_network "$S_RANGE" ;;
        2) listen_universal ;;
        3) run_interrogation ;;
        4) auto_fetch_rtsp ;;
        5) DET_IP=""; cleanup ;;
        6) cleanup; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
