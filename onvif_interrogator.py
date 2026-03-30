import sys
import os
from urllib.error import URLError
try:
    from onvif import ONVIFCamera
except ImportError:
    print("FAILED: onvif_zeep package not installed. Please install it in the virtual environment.")
    sys.exit(1)

def attempt_onvif_extraction(ip, user, password, port):
    """
    Attempts to connect to the camera via ONVIF and extract:
    - Device Information (Manufacturer, Model, Firmware, Serial)
    - Capabilities (Network, Media, PTZ, Events)
    - RTSP Stream URI
    """
    results = {
        "device_info": {},
        "capabilities": {},
        "rtsp_url": None,
        "success": False
    }

    try:
        # The library requires a username/password, but empty strings often work for unauthenticated requests
        mycam = ONVIFCamera(ip, port, user, password)

        # 1. Get Device Information
        try:
            dev_service = mycam.create_devicemgmt_service()
            dev_info = dev_service.GetDeviceInformation()
            results["device_info"] = {
                "Manufacturer": getattr(dev_info, 'Manufacturer', 'Unknown'),
                "Model": getattr(dev_info, 'Model', 'Unknown'),
                "FirmwareVersion": getattr(dev_info, 'FirmwareVersion', 'Unknown'),
                "SerialNumber": getattr(dev_info, 'SerialNumber', 'Unknown'),
                "HardwareId": getattr(dev_info, 'HardwareId', 'Unknown')
            }
            results["success"] = True
        except Exception as e:
            pass # We'll just continue if device info fails, maybe media works

        # 2. Get Capabilities
        try:
            # We use an empty dict as zeep often expects an object for this call
            capabilities = dev_service.GetCapabilities({'Category': 'All'})
            if hasattr(capabilities, 'Device'):
                results["capabilities"]["Device"] = "Supported"
            if hasattr(capabilities, 'Media'):
                results["capabilities"]["Media"] = "Supported"
            if hasattr(capabilities, 'PTZ'):
                results["capabilities"]["PTZ"] = "Supported"
            if hasattr(capabilities, 'Events'):
                results["capabilities"]["Events"] = "Supported"
        except Exception as e:
            pass

        # 3. Get RTSP URL (Graceful approach)
        try:
            media_service = mycam.create_media_service()
            profiles = media_service.GetProfiles()

            if profiles:
                stream_setup = {
                    'Stream': 'RTP-Unicast',
                    'Transport': {'Protocol': 'RTSP'}
                }

                uri_obj = media_service.GetStreamUri({
                    'StreamSetup': stream_setup,
                    'ProfileToken': profiles[0].token
                })

                if uri_obj and hasattr(uri_obj, 'Uri'):
                    results["rtsp_url"] = uri_obj.Uri
                    results["success"] = True
        except Exception as e:
            pass

        return results

    except Exception as e:
        # Connection or Authentication Failure
        return results

def main():
    if len(sys.argv) < 3:
        print("Usage: python onvif_interrogator.py <IP> <CREDS_FILE>")
        sys.exit(1)

    target_ip = sys.argv[1]
    creds_file = sys.argv[2]

    ports_to_try = [80, 8080, 8888, 8000, 5000]

    # We will prioritize unauthenticated attempts first
    credentials = [("", "")] # Empty user/pass for unauthenticated

    if os.path.exists(creds_file):
        with open(creds_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split(':', 1)
                    if len(parts) == 2:
                        credentials.append((parts[0], parts[1]))

    final_results = None
    successful_cred = None
    successful_port = None

    # Try all credentials against all common ports
    for user, password in credentials:
        cred_display = "Unauthenticated" if not user else f"User: {user}"
        for port in ports_to_try:
            results = attempt_onvif_extraction(target_ip, user, password, port)

            if results["success"]:
                final_results = results
                successful_cred = cred_display
                successful_port = port
                break

        if final_results:
            break

    if not final_results:
        print("ONVIF Enumeration FAILED: Could not connect or authenticate.")
        sys.exit(0)

    # Output the results
    print(f"\n--- ONVIF ENUMERATION SUCCESS ---")
    print(f"Connection: Port {successful_port} ({successful_cred})")

    if final_results["device_info"]:
        print("\nDevice Information:")
        for k, v in final_results["device_info"].items():
            print(f"  {k}: {v}")

    if final_results["capabilities"]:
        print("\nSupported Capabilities:")
        for k, v in final_results["capabilities"].items():
            print(f"  - {k}")

    if final_results["rtsp_url"]:
        print("\nGraceful RTSP Extraction:")
        print(f"  URL: {final_results['rtsp_url']}")
        # We output this specific string so bash can grep it easily
        print(f"SUCCESS_URL:{final_results['rtsp_url']}")
    else:
        print("\nGraceful RTSP Extraction: FAILED")

if __name__ == '__main__':
    main()
