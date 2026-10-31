import json
import os
from pathlib import Path
import secrets
import sys

from werkzeug.security import generate_password_hash

sys.path.insert(0, "/opt/adsb/adsb-setup")
from utils.loft_receiver import validate_config

PROVISIONED = Path("/etc/loft-receiver/provisioned")
BOOT_CONFIG = Path("/boot/firmware/loft.json")
CREDENTIALS = Path("/root/loft-credentials.txt")
ENV_FILE = Path("/opt/adsb/config/.env")
RADIO_CONFIG = Path("/etc/loft-receiver/radio.json")


def main():
    done = PROVISIONED
    if done.exists():
        return
    boot = BOOT_CONFIG
    values = json.loads(boot.read_text()) if boot.exists() else {}
    if not isinstance(values, dict):
        raise ValueError("loft.json must contain an object")
    if set(values) - {"web_password", "receiver"}:
        raise ValueError("loft.json accepts only web_password and receiver")
    password = values["web_password"] if "web_password" in values else secrets.token_urlsafe(24)
    if not isinstance(password, str) or len(password) < 12 or "\n" in password:
        raise ValueError("web_password must be at least 12 characters and contain no newlines")
    if password.startswith("REPLACE_WITH_"):
        raise ValueError("Replace the example web_password with a unique password")
    receiver = validate_config(values["receiver"]) if "receiver" in values else None
    if receiver and receiver["serial"] == "00000001":
        raise ValueError("The streaming serial conflicts with the default ADS-B dongle")
    os.umask(0o077)
    credentials = CREDENTIALS
    credentials.write_text(f"Feeder web login: admin\nPassword: {password}\n")
    env = ENV_FILE
    with env.open("a") as file:
        file.write("\n_ADSBIM_WEB_AUTH_ENABLED=True\n_ADSBIM_WEB_AUTH_USERNAME=admin\n")
        file.write(f"_ADSBIM_WEB_AUTH_PASSWORD_HASH={generate_password_hash(password)}\n")
    env.chmod(0o600)
    if receiver:
        config = RADIO_CONFIG
        config.write_text(json.dumps(receiver) + "\n")
        config.chmod(0o644)
    if boot.exists():
        boot.unlink()
    done.touch()


if __name__ == "__main__":
    main()
