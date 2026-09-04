# API & Service Interface Reference

This document provides a comprehensive reference for all CLI interfaces, network endpoints, SOAP/ONVIF RPC services, WS-Discovery multicast schemas, security evaluation plugin interfaces, and report file data schemas in `camera_tools`.

---

## 1. Overview & Service Interfaces

`camera_tools` interacts with IP cameras and network video devices across multiple layers:
- **Multicast Discovery**: WS-Discovery over UDP port 3702 (`239.255.255.250`).
- **ONVIF Web Services**: SOAP over HTTP (common ports: 80, 8080, 8888, 8000, 5000).
- **RTSP Media Streaming**: Real-Time Streaming Protocol over TCP/UDP port 554.
- **Plaintext / Management Services**: HTTP (80), FTP (21), Telnet (23), SSH (22).
- **Python Security Plugin Interface**: Dynamic module loading via `security_plugins/*.py`.

---

## 2. CLI Script Interfaces

### 2.1 `main.sh` (Interactive Orchestrator)
The interactive menu interface for network discovery, packet capture, device interrogation, RTSP path fetching, and security evaluations.

* **Invocation**:
  ```bash
  sudo ./main.sh
  ```
* **Environment Dependencies**:
  * `camera_env` virtual environment present at `./camera_env`.
  * `camera_creds.txt` containing default credentials in `username:password` format.
* **Outputs**:
  * Device logs created under `./device_logs/<Vendor>/<Model>/<Name>/`.

---

### 2.2 `onvif_interrogator.py`
Enumerates ONVIF device information, capabilities, and stream URIs using unauthenticated attempts followed by credentials listed in `camera_creds.txt`.

* **CLI Syntax**:
  ```bash
  python3 onvif_interrogator.py <IP> <CREDS_FILE>
  ```
* **Parameters**:
  | Parameter | Type | Required | Description |
  | :--- | :--- | :--- | :--- |
  | `IP` | String | Yes | Target camera IP address (e.g., `192.168.1.100`). |
  | `CREDS_FILE` | String | Yes | Path to credentials file (e.g., `camera_creds.txt`). |

* **Standard Output Schema**:
  ```text
  --- ONVIF ENUMERATION SUCCESS ---
  Connection: Port 80 (Unauthenticated)

  Device Information:
    Manufacturer: Hikvision
    Model: DS-2CD2143G0-I
    FirmwareVersion: V5.5.80
    SerialNumber: DS-2CD2143G0-I20190101AAWR123456789
    HardwareId: 1.0

  Supported Capabilities:
    - Device
    - Media

  Graceful RTSP Extraction:
    URL: rtsp://192.168.1.100:554/Streaming/Channels/101
  SUCCESS_URL:rtsp://192.168.1.100:554/Streaming/Channels/101
  ```
* **Exit Codes**:
  * `0`: Completed execution (outputs results or `ONVIF Enumeration FAILED`).
  * `1`: Invalid arguments or missing dependency (`onvif_zeep`).

---

### 2.3 `get_rtsp_path.py`
Attempts ONVIF authentication over standard web ports (`80`, `8080`, `8888`, `8000`, `5000`) and retrieves the primary RTSP stream URI for a given credential pair.

* **CLI Syntax**:
  ```bash
  python3 get_rtsp_path.py <IP> <USER> <PASS>
  ```
* **Parameters**:
  | Parameter | Type | Required | Description |
  | :--- | :--- | :--- | :--- |
  | `IP` | String | Yes | Target IP address. |
  | `USER` | String | Yes | ONVIF username. |
  | `PASS` | String | Yes | ONVIF password. |

* **Success Output**:
  ```text
  SUCCESS_URL:rtsp://192.168.1.100:554/live/main
  ```
* **Failure Output**:
  ```text
  FAILED: No ONVIF service found or authentication failed.
  ```

---

### 2.4 `ws_discovery_listener.py`
Background daemon that binds to UDP port 3702, joins multicast group `239.255.255.250`, captures `Hello` and `ProbeMatches` XML payloads, and writes raw XML and extracted summaries to a directory.

* **CLI Syntax**:
  ```bash
  python3 ws_discovery_listener.py <INTERFACE_IP> <TEMP_DIR>
  ```
* **Parameters**:
  | Parameter | Type | Required | Description |
  | :--- | :--- | :--- | :--- |
  | `INTERFACE_IP` | String | Yes | Local IP address of listening network interface (e.g., `10.254.254.1`). |
  | `TEMP_DIR` | String | Yes | Target folder for raw XML and text summaries (e.g., `/tmp/ws_discovery_data`). |

---

### 2.5 `security_evaluator.py`
Parses the nmap/ONVIF MAC report file, tests open ports (FTP, Telnet, SSH) against credential lists, and dynamically executes security evaluation plugins.

* **CLI Syntax**:
  ```bash
  python3 security_evaluator.py <IP> <MAC_FILE_PATH> <CREDS_FILE>
  ```
* **Parameters**:
  | Parameter | Type | Required | Description |
  | :--- | :--- | :--- | :--- |
  | `IP` | String | Yes | Target camera IP address. |
  | `MAC_FILE_PATH` | String | Yes | Path to interrogation report (e.g., `./device_logs/Hikvision/DS-2CD2143G0-I/Front_Door/00e04c6800f5.txt`). |
  | `CREDS_FILE` | String | Yes | Path to credentials file (e.g., `camera_creds.txt`). |

---

### 2.6 `rtsp_brute.sh`
Brute-forces common RTSP streaming paths and credentials using `ffprobe`.

* **CLI Syntax**:
  ```bash
  ./rtsp_brute.sh <IP_ADDRESS>
  ```
* **Tested Paths**:
  * `/`
  * `/live/ch0`
  * `/stream1`
  * `/Streaming/Channels/101`
  * `/onvif-media-stream`
  * `/live/main`
* **Output Log**: Appends valid RTSP URLs to `./device_logs/credentials_found.log`.

---

## 3. WS-Discovery Multicast Interface

### Multicast Parameters
* **Group Address**: `239.255.255.250`
* **Port**: `3702` (UDP)
* **Namespaces**:
  ```xml
  xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
  xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing"
  xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
  ```

### Sample WS-Discovery XML Payload (`ws_discovery_<IP>_raw.xml`)
```xml
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
               xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing"
               xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
  <soap:Header>
    <wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Hello</wsa:Action>
    <wsa:MessageID>urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890</wsa:MessageID>
    <wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
  </soap:Header>
  <soap:Body>
    <d:Hello>
      <wsa:EndpointReference>
        <wsa:Address>urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890</wsa:Address>
      </wsa:EndpointReference>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
      <d:Scopes>onvif://www.onvif.org/type/NetworkVideoTransmitter onvif://www.onvif.org/name/IP_Camera</d:Scopes>
      <d:XAddrs>http://192.168.1.100:80/onvif/device_service</d:XAddrs>
      <d:MetadataVersion>1</d:MetadataVersion>
    </d:Hello>
  </soap:Body>
</soap:Envelope>
```

### Parsed Summary Output Schema (`ws_discovery_<IP>_info.txt`)
```text
=== WS-Discovery Information ===
Message Type: Hello
Source IP: 192.168.1.100
Endpoint Reference: urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890
Device Types: dn:NetworkVideoTransmitter
Scopes:
  - onvif://www.onvif.org/type/NetworkVideoTransmitter
  - onvif://www.onvif.org/name/IP_Camera
XAddrs (Service URLs):
  - http://192.168.1.100:80/onvif/device_service
```

---

## 4. ONVIF SOAP & Media Interface Specifications

### 4.1 Device Management Service (`GetDeviceInformation`)
* **Endpoint**: `http://<IP>:<PORT>/onvif/device_service`
* **SOAP Action**: `http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation`
* **Response Data Schema**:
  ```json
  {
    "Manufacturer": "String",
    "Model": "String",
    "FirmwareVersion": "String",
    "SerialNumber": "String",
    "HardwareId": "String"
  }
  ```

### 4.2 Media Service (`GetStreamUri`)
* **Endpoint**: `http://<IP>:<PORT>/onvif/media_service`
* **SOAP Action**: `http://www.onvif.org/ver10/media/wsdl/GetStreamUri`
* **Request Envelope Structure**:
  ```json
  {
    "StreamSetup": {
      "Stream": "RTP-Unicast",
      "Transport": {
        "Protocol": "RTSP"
      }
    },
    "ProfileToken": "Profile_1"
  }
  ```
* **Response Data Structure**:
  ```json
  {
    "Uri": "rtsp://192.168.1.100:554/Streaming/Channels/101"
  }
  ```

---

## 5. Security Evaluation Plugin Interface

Plugins placed in `security_plugins/` are dynamically imported by `security_evaluator.py`.

### Required Python Module Structure
* **File Naming**: `security_plugins/<plugin_name>.py` (excluding `__init__.py`)
* **Required Function**: `run(target_data)`

### Entry Point Contract
```python
def run(target_data: dict) -> list[str]:
    """
    Executes security vulnerability checks against target device metadata.

    :param target_data: Dictionary containing parsed device metadata.
    :return: List of string findings/vulnerability messages.
    """
    findings = []
    # Inspection logic...
    return findings
```

### `target_data` Input Dictionary Schema
```json
{
  "ip": "192.168.1.100",
  "vendor": "Hikvision",
  "model": "DS-2CD2143G0-I",
  "firmware": "V5.5.80",
  "open_ports": {
    "21": "ftp",
    "23": "telnet",
    "80": "http",
    "554": "rtsp"
  },
  "onvif_unauth": false,
  "rtsp_url": "rtsp://192.168.1.100:554/Streaming/Channels/101"
}
```

---

## 6. Report Envelopes & File Schemas

### Interrogation & Security Report Schema (`<MAC_STR>.txt`)
```text
=== INTERROGATION REPORT ===
IP: 192.168.1.100 | MAC: 00:e0:4c:68:00:f5 | Vendor: Hikvision
--------------------------------------
Starting Nmap 7.80 ( https://nmap.org ) at 2026-03-31 12:00 UTC
Nmap scan report for 192.168.1.100
Host is up (0.0020s latency).
PORT    STATE SERVICE VERSION
21/tcp  open  ftp     vsftpd 3.0.3
23/tcp  open  telnet  BusyBox telnetd
80/tcp  open  http    lighttpd 1.4.53
554/tcp open  rtsp

=== ONVIF ENUMERATION ===
Attempting graceful extraction (unauthenticated first, then brute-force)...
--- ONVIF ENUMERATION SUCCESS ---
Connection: Port 80 (Unauthenticated)

Device Information:
  Manufacturer: Hikvision
  Model: DS-2CD2143G0-I
  FirmwareVersion: V5.5.80
  SerialNumber: DS-2CD2143G0-I20190101AAWR123456789
  HardwareId: 1.0

Supported Capabilities:
  - Device
  - Media

Graceful RTSP Extraction:
  URL: rtsp://192.168.1.100:554/Streaming/Channels/101
SUCCESS_URL:rtsp://192.168.1.100:554/Streaming/Channels/101

========================================
       SECURITY EVALUATION REPORT
========================================
Target IP: 192.168.1.100
Device: Hikvision DS-2CD2143G0-I
Firmware: V5.5.80
----------------------------------------

[ BASELINE ASSESSMENT ]
  WARNING: Insecure Protocol FTP (Port 21) is OPEN. Transmits files and credentials in plaintext.
  CRITICAL: FTP default credentials found (admin:12345) on Port 21
  WARNING: Insecure Protocol Telnet (Port 23) is OPEN. Transmits all data, including management credentials, in plaintext.
  CRITICAL: Telnet default credentials found (root:pass) on Port 23
  WARNING: Insecure Protocol HTTP (Port 80) is OPEN. Unencrypted web management interface. Vulnerable to interception.

[ PLUGIN ASSESSMENT ]
--- Plugin: check_firmware_cves.py ---
  CRITICAL: Telnet is enabled by default on this firmware version. High risk of botnet infection (Mirai).
========================================
```
