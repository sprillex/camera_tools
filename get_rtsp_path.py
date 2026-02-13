import sys
from onvif import ONVIFCamera

def get_rtsp_url(ip, user, password):
    """
    Connects to a camera via ONVIF and retrieves the RTSP Stream URI.
    """
    # Common ports used by different manufacturers for ONVIF/Web services
    ports = [80, 8080, 8888, 8000, 5000]

    for port in ports:
        try:
            # Initialize the camera connection
            # wsdl_dir is usually handled automatically by the library
            mycam = ONVIFCamera(ip, port, user, password)

            # Create the media service to handle stream requests
            media_service = mycam.create_media_service()

            # Get available profiles (e.g., Main Stream, Sub Stream)
            profiles = media_service.GetProfiles()

            if not profiles:
                continue

            # Define the transport setup for RTSP
            stream_setup = {
                'Stream': 'RTP-Unicast',
                'Transport': {'Protocol': 'RTSP'}
            }

            # Request the URI for the first available profile (usually the highest quality)
            uri_obj = media_service.GetStreamUri({
                'StreamSetup': stream_setup,
                'ProfileToken': profiles[0].token
            })

            # The SUCCESS_URL prefix is used by main.sh to parse the result
            if uri_obj and hasattr(uri_obj, 'Uri'):
                print(f"SUCCESS_URL:{uri_obj.Uri}")
                return

        except Exception:
            # Silently fail and try the next port in the list
            continue

    print("FAILED: No ONVIF service found or authentication failed.")

if __name__ == "__main__":
    # Ensure the script receives the necessary arguments from main.sh
    if len(sys.argv) < 4:
        print("Usage: python get_rtsp_path.py <IP> <USER> <PASS>")
        sys.exit(1)

    target_ip = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    get_rtsp_url(target_ip, username, password)
