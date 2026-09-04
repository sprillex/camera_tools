import re

def run(target_data):
    """
    Checks if the firmware version is susceptible to a known hypothetical CVE.
    In a real scenario, this plugin might query an external API or run
    an active HTTP request against the camera.
    """
    findings = []
    firmware = target_data.get("firmware", "")
    vendor = target_data.get("vendor", "")

    if not firmware:
        return ["INFO: No firmware version found to evaluate."]

    # Example Logic: Generic vendor check
    if "Generic" in vendor or "Unknown" in vendor:
        findings.append("WARNING: Generic or white-labeled devices often have hardcoded backdoors (e.g., CVE-202X-XXXXX). Verify OEM origin.")

    # Example Logic: Specific firmware version matching
    # e.g., if firmware starts with 1.4.x
    match = re.search(r'^1\.4\.', firmware)
    if match:
        findings.append("CRITICAL: Firmware branch 1.4.x is vulnerable to Remote Code Execution via RTSP buffer overflow (CVE-2019-XXXX). Immediate patch required.")

    # Check if Telnet is open on this specific firmware
    if 23 in target_data.get("open_ports", {}):
        findings.append("CRITICAL: Telnet is enabled by default on this firmware version. High risk of botnet infection (Mirai).")

    return findings
