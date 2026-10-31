import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, "/opt/adsb/adsb-setup")
from utils.loft_receiver import validate_config


def main():
    config = Path("/etc/loft-receiver/radio.json")
    settings = validate_config(json.loads(config.read_text())) if config.exists() else None
    if sys.argv[1:] == ["--firewall"]:
        existing = subprocess.run(["nft", "list", "table", "inet", "loft_receiver"], capture_output=True)
        rules = "delete table inet loft_receiver\n" if existing.returncode == 0 else ""
        restrictions = (
            f"ip saddr != {settings['hub_client']} tcp dport 1234 drop\n"
            f"ip saddr != {settings['adsb_client']} tcp dport 30005 drop"
            if settings else "tcp dport { 1234, 30005 } drop"
        )
        rules += f"""
table inet loft_receiver {{
    chain ingress {{
        type filter hook prerouting priority -310; policy accept;
        {restrictions}
        meta nfproto ipv6 tcp dport {{ 1234, 30005 }} drop
    }}
}}
"""
        subprocess.run(["nft", "-f", "-"], input=rules, text=True, check=True)
        return
    if settings is None:
        raise ValueError("Configure the receiver before starting RTL-TCP")
    if sys.argv[1:] == ["--check-assignment"]:
        # Root-only preflight avoids granting the radio user access to feeder credentials.
        env = Path("/opt/adsb/config/.env").read_text().splitlines()
        for line in env:
            if line.startswith("FEEDER_SERIAL_") and line.partition("=")[2].strip("'\" ") == settings["serial"]:
                raise ValueError("Streaming dongle has been assigned to a feeder decoder")
        return
    if sys.argv[1:]:
        raise ValueError("Expected no arguments, --check-assignment or --firewall")
    os.execvp("rtl_tcp", [
        "rtl_tcp", "-a", settings["listen"], "-p", "1234",
        "-d", settings["serial"], "-s", "1024000", "-f", "100000000",
    ])


if __name__ == "__main__":
    main()
