#!/usr/bin/env python3
import scapy.all as scapy
import json
import socket
import ipaddress
import sys
import os

def detect_local_network():
    """
    Detects the local IP address and suggests a /24 subnet.
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Connect to a public DNS server to determine the local interface IP used for routing
        # The connection is not actually established, so no traffic is sent
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
    except Exception:
        local_ip = '127.0.0.1'
    finally:
        s.close()

    if local_ip == '127.0.0.1':
        return '127.0.0.1/8'

    # Suggest a /24 subnet based on the local IP
    try:
        network = ipaddress.IPv4Network(f"{local_ip}/24", strict=False)
        return str(network)
    except ValueError:
        return f"{local_ip}/24"

def get_target_network(default_network):
    """
    Prompts the user to confirm the detected network or enter a new one.
    """
    print(f"\nDetected default network: {default_network}")

    while True:
        user_input = input(f"Enter the network to scan (Press Enter to use {default_network}): ").strip()

        if not user_input:
            return default_network

        # Validate user input
        try:
            ipaddress.IPv4Network(user_input, strict=False)
            return user_input
        except ValueError:
            print(f"Invalid network format: {user_input}. Please use CIDR notation (e.g., 192.168.1.0/24).")

def scan_network(network):
    """
    Performs an ARP scan on the specified network using Scapy.
    Returns a list of dictionaries containing device details.
    """
    print(f"\nStarting scan on {network}...")

    try:
        # Create ARP request packet
        arp_request = scapy.ARP(pdst=network)
        # Create Ethernet frame for broadcast
        broadcast = scapy.Ether(dst="ff:ff:ff:ff:ff:ff")
        # Combine them
        arp_request_broadcast = broadcast/arp_request

        # Send and receive packets
        # timeout=2 ensures we don't wait forever
        # verbose=False suppresses scapy's own output
        answered_list = scapy.srp(arp_request_broadcast, timeout=2, verbose=False)[0]

        clients_list = []
        for element in answered_list:
            client_dict = {
                "ip": element[1].psrc,
                "mac": element[1].hwsrc
            }

            # Attempt to resolve hostname
            try:
                hostname = socket.gethostbyaddr(element[1].psrc)[0]
                client_dict["hostname"] = hostname
            except (socket.herror, socket.gaierror):
                client_dict["hostname"] = "Unknown"

            clients_list.append(client_dict)

        return clients_list

    except PermissionError:
        print("Error: Permission denied. Please run this script with sudo or as root.")
        sys.exit(1)
    except Exception as e:
        print(f"An error occurred during scanning: {e}")
        sys.exit(1)

def save_results(results, filename="network_scan_results.json"):
    """
    Saves the scan results to a JSON file.
    """
    try:
        with open(filename, 'w') as f:
            json.dump(results, f, indent=4)
        print(f"\nResults saved to {filename}")
        print(f"Found {len(results)} devices.")
    except IOError as e:
        print(f"Error saving results to file: {e}")

def main():
    print("Network Scanner Tool")
    print("--------------------")

    default_network = detect_local_network()
    target_network = get_target_network(default_network)

    scan_results = scan_network(target_network)

    if scan_results:
        print("\nScan Results:")
        print(f"{'IP Address':<20} {'MAC Address':<20} {'Hostname'}")
        print("-" * 60)
        for client in scan_results:
            print(f"{client['ip']:<20} {client['mac']:<20} {client['hostname']}")

        save_results(scan_results)
    else:
        print("\nNo devices found on the network.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nScan interrupted by user.")
        sys.exit(0)
