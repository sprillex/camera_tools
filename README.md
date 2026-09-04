# camera_tools

`camera_tools` is an extensible security research and interrogation toolkit designed for discovery, traffic capture, ONVIF service enumeration, RTSP stream URL extraction, and security evaluation of IP cameras. Orchestrated via Bash and Python scripts, it automates multi-stage network boot traps, WS-Discovery sniffing, default credential testing, and modular vulnerability analysis.

---

## Features

- **Multi-Subnet Active Ping & ARP Discovery**: Scans target subnets using `arp-scan` and `nmap` with active route finalization.
- **Universal Boot Trap (90s Harvest Window)**: Captures DHCP requests, raw IPv4 packet traffic, and WS-Discovery multicast messages (`239.255.255.250:3702`) during camera boot cycles.
- **Smart Subnet Validation**: Safely checks candidate IP addresses across subnets with overlap verification to prevent routing table conflicts.
- **Automated Interrogation & Packet Capture**: Performs nmap service detection, OS fingerprinting, and concurrent `tcpdump` PCAP recording.
- **Graceful ONVIF Enumeration**: Extracts device metadata (manufacturer, model, firmware, serial number) and RTSP stream URIs, trying unauthenticated access before falling back to default credentials.
- **RTSP Path & Credential Brute-Forcing**: Automates stream URL retrieval via `onvif_zeep` and path testing via `ffprobe`.
- **Extensible Security Evaluation Framework**: Assesses plaintext protocols (FTP, Telnet, HTTP) and default credentials, and dynamically executes security plugins located in `security_plugins/`.

---

## Tech Stack & Architecture

- **Orchestration**: Bash (`main.sh`, `rtsp_brute.sh`, `setup_env.sh`).
- **Core Runtime**: Python 3.8+ virtual environment (`./camera_env`).
- **Networking Tools**: `nmap`, `arp-scan`, `arping`, `tcpdump`, `dnsmasq`, `iproute2`, `NetworkManager` (`nmcli`).
- **Python Libraries**:
  - `onvif-zeep`: ONVIF SOAP web services interface.
  - `paramiko`: SSH authentication testing.
  - `telnetlib`: Telnet banner and login verification.
  - `ftplib`: FTP anonymous and default credential checking.
- **Storage Layer**: Directory-based file hierarchy structured as `./device_logs/<Vendor>/<Model>/<Camera_Name>/`.

---

## Repository Layout

```text
.
├── main.sh                  # Interactive CLI orchestrator and menu runner
├── setup_env.sh             # Environment setup script creating ./camera_env
├── onvif_interrogator.py    # ONVIF device info, capability, and RTSP extractor
├── get_rtsp_path.py         # Dedicated ONVIF RTSP stream URI fetcher
├── ws_discovery_listener.py # Multicast WS-Discovery listener (UDP 3702)
├── security_evaluator.py    # Baseline security audit and plugin runner
├── rtsp_brute.sh            # FFprobe RTSP credential/path brute-forcer
├── camera_creds.txt         # Wordlist of default camera credentials (user:pass)
├── requirements.txt         # Python dependencies file
├── security_plugins/        # Directory for dynamic security check plugins
│   ├── __init__.py
│   └── check_firmware_cves.py
└── device_logs/             # Output log directory for PCAPs and text reports
```

---

## Prerequisites & Setup

### Prerequisites
- **Operating System**: Linux (Ubuntu/Debian recommended).
- **System Packages**: `sudo`, `iproute2`, `network-manager`, `nmap`, `arp-scan`, `tcpdump`, `dnsmasq`, `ffmpeg` (for `ffprobe`), `python3`, `python3-venv`, `python3-pip`.

### Step-by-Step Setup
1. **Clone the Repository**:
   ```bash
   git clone <repository_url>
   cd camera_tools
   ```

2. **Initialize Environment & Dependencies**:
   Run the setup script to create the Python virtual environment `./camera_env` and install required dependencies:
   ```bash
   chmod +x setup_env.sh main.sh rtsp_brute.sh
   ./setup_env.sh
   ```

   Alternatively, manually create the virtual environment and install dependencies:
   ```bash
   python3 -m venv camera_env
   source camera_env/bin/activate
   pip install --upgrade pip
   pip install -r requirements.txt
   ```

---

## Configuration

- **Target MAC Address**: Edit `TARGET_MAC` near the top of `main.sh`:
  ```bash
  TARGET_MAC="00:e0:4c:68:00:f5"
  ```
- **Temporary Host Suffix**: Set `MY_TEMP_IP` in `main.sh` (default: `250`).
- **Credentials List**: Update `camera_creds.txt` with targeted default credentials (`username:password` format):
  ```text
  admin:admin
  admin:12345
  root:pass
  ```
- **Virtual Environment Path**: Configured as `VENV_PATH="./camera_env/bin/activate"` in `main.sh`.

---

## Running the Application

Launch the main interactive toolkit orchestrator with `sudo` privileges (required for packet capture and network interface configuration):

```bash
sudo ./main.sh
```

### Menu Options Overview
1. **Active Ping Discovery**: Scans configurable CIDR blocks or default subnets (`192.168.1.0/24`, `192.168.0.0/24`, `10.0.0.0/24`).
2. **Universal Boot Trap**: Starts a 90-second DHCP server, packet capture, and WS-Discovery listener for camera boot-up analysis.
3. **Interrogate & Capture**: Runs `nmap` OS/service detection, captures PCAP traffic, and executes ONVIF enumeration.
4. **Auto-Fetch RTSP**: Performs RTSP stream extraction using ONVIF credentials.
5. **Run Security Evaluation**: Audits open ports, tests default credentials on FTP/Telnet/SSH, and runs custom plugins in `security_plugins/`.
6. **Reset / Clear Target**: Restores network interface settings and cleans up background processes.

---

## Testing & Verification

Run syntax checks and compilation tests to verify script integrity across the project:

### Shell Script Syntax Check
```bash
bash -n main.sh rtsp_brute.sh setup_env.sh
```

### Python Bytecode Compilation Test
```bash
python3 -m py_compile get_rtsp_path.py onvif_interrogator.py security_evaluator.py ws_discovery_listener.py security_plugins/check_firmware_cves.py
```

---

## API & Service Reference

Detailed specifications for CLI parameters, ONVIF SOAP actions, WS-Discovery multicast formats, security evaluation plugin contracts, and report file schemas are documented in [API.md](./API.md).
