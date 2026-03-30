import sys
import socket
import struct
import signal
import os
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

# WS-Discovery Configuration
MULTICAST_GROUP = '239.255.255.250'
PORT = 3702

# XML Namespaces mapping for WS-Discovery
NAMESPACES = {
    'soap': 'http://www.w3.org/2003/05/soap-envelope',
    'wsa': 'http://schemas.xmlsoap.org/ws/2004/08/addressing',
    'd': 'http://schemas.xmlsoap.org/ws/2005/04/discovery'
}

def setup_multicast_socket(interface_ip):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # Bind to all interfaces on port 3702
    sock.bind(('', PORT))

    # Join the multicast group on the specific interface
    mreq = struct.pack("4s4s", socket.inet_aton(MULTICAST_GROUP), socket.inet_aton(interface_ip))
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    return sock

def parse_ws_discovery(xml_data, ip_addr, temp_dir):
    try:
        # Save raw XML first
        raw_filename = os.path.join(temp_dir, f"ws_discovery_{ip_addr}_raw.xml")
        if not os.path.exists(raw_filename):
            with open(raw_filename, 'wb') as f:
                f.write(xml_data)

        # Parse XML
        root = ET.fromstring(xml_data)

        # Check if it's a Hello message or generic ProbeMatch
        body = root.find('soap:Body', NAMESPACES)
        header = root.find('soap:Header', NAMESPACES)

        if body is None or header is None:
            return

        action = header.find('wsa:Action', NAMESPACES)
        if action is None:
            return

        action_text = action.text.strip()
        message_type = "Unknown"
        if "Hello" in action_text:
            message_type = "Hello"
        elif "ProbeMatches" in action_text:
            message_type = "ProbeMatch"
        else:
            return # Ignore other types for now

        target_node = body.find(f'd:{message_type}', NAMESPACES)
        if target_node is None and message_type == "ProbeMatch":
            # Sometimes nested in ProbeMatches
            matches = body.find('d:ProbeMatches', NAMESPACES)
            if matches is not None:
                target_node = matches.find('d:ProbeMatch', NAMESPACES)

        if target_node is None:
            return

        endpoint = target_node.find('.//wsa:Address', NAMESPACES)
        types = target_node.find('.//d:Types', NAMESPACES)
        scopes = target_node.find('.//d:Scopes', NAMESPACES)
        xaddrs = target_node.find('.//d:XAddrs', NAMESPACES)

        info_filename = os.path.join(temp_dir, f"ws_discovery_{ip_addr}_info.txt")

        # Only write if we haven't already for this IP
        if not os.path.exists(info_filename):
            with open(info_filename, 'w') as f:
                f.write("=== WS-Discovery Information ===\n")
                f.write(f"Message Type: {message_type}\n")
                f.write(f"Source IP: {ip_addr}\n")

                if endpoint is not None and endpoint.text:
                    f.write(f"Endpoint Reference: {endpoint.text.strip()}\n")

                if types is not None and types.text:
                    f.write(f"Device Types: {types.text.strip()}\n")

                if scopes is not None and scopes.text:
                    f.write("Scopes:\n")
                    for scope in scopes.text.strip().split():
                        f.write(f"  - {scope}\n")

                if xaddrs is not None and xaddrs.text:
                    f.write("XAddrs (Service URLs):\n")
                    for xaddr in xaddrs.text.strip().split():
                        f.write(f"  - {xaddr}\n")

            print(f"[WS-Discovery] Captured and parsed data for {ip_addr}")

    except ET.ParseError:
        print(f"Failed to parse XML from {ip_addr}")
    except Exception as e:
        print(f"Error processing WS-Discovery: {e}")

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 ws_discovery_listener.py <interface_ip> <temp_dir>")
        sys.exit(1)

    interface_ip = sys.argv[1]
    temp_dir = sys.argv[2]

    os.makedirs(temp_dir, exist_ok=True)

    try:
        sock = setup_multicast_socket(interface_ip)
        print(f"Listening for WS-Discovery on {interface_ip} (Temp Dir: {temp_dir})...")

        while True:
            data, addr = sock.recvfrom(65535)
            # Only process if it's from a different IP than ourselves
            if addr[0] != interface_ip:
                parse_ws_discovery(data, addr[0], temp_dir)

    except KeyboardInterrupt:
        print("Shutting down WS-Discovery listener...")
    except Exception as e:
        print(f"Fatal Error: {e}")
    finally:
        sock.close()

if __name__ == '__main__':
    main()
