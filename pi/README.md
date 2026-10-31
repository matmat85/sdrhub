# Raspberry Pi Zero 2 W receiver

## Flash and configure

Download `loft-pi.img.xz` and verify it against the release's `SHA256SUMS`.
With Raspberry Pi Imager 2, load the release catalogue:

```text
rpi-imager --repo https://github.com/matmat85/sdrhub/releases/download/v0.1.1/pi-imager.json
```

Select Raspberry Pi Zero 2 W and Loft SDR receiver. Configure your own username,
password, hostname, SSH access, 2.4 GHz Wi-Fi and wireless country in Imager.
The catalogue advertises `cloudinit-rpi`, matching the pinned Raspberry Pi OS
Trixie base. No OS account, password, Wi-Fi credential or SSH key is baked in.

Alternatively choose **Use custom** and the downloaded image, then place your
local cloud-init `user-data` and `network-config` on the FAT boot partition.
Raspberry Pi OS Trixie supports cloud-init provisioning; use the
[official cloud-init instructions](https://www.raspberrypi.com/documentation/computers/configuration.html).
Do not assume Imager customization is offered when using an image without the
catalogue metadata. Verify the boot partition contains your provisioning files
before powering on.

For web setup without first retrieving a generated password over SSH, copy
`loft.example.json` to **loft.json** on the FAT boot partition and replace all
example values. It accepts a unique `web_password` (at least 12 characters) and
optional `receiver` settings. Reserve the Pi and LXC addresses in your router.
The file is removed after successful provisioning, but removal is not secure
erasure on an SD card; do not reuse this password elsewhere.

Without `loft.json`, the Pi generates unique web credentials on first boot.
SSH using your Imager-created account and run:

```bash
sudo cat /root/loft-credentials.txt
```

Open `http://PI_ADDRESS:1099`, log in as `admin`, and:

1. Set the receiver's location. Keep **Nano** selected: no Pi-side aggregators
   or graphs are needed.
2. In **SDR Setup**, assign serial `00000001` to 1090 and leave `77465553`
   unassigned. Bias tees should remain off.
3. Open **Loft receiver settings**. Enter the second dongle serial, Pi IPv4,
   SDR Hub LXC IPv4 and ADS-B LXC IPv4.

The Pi decodes ADS-B with the upstream Nano configuration and exposes Beast
on TCP 30005. The second radio uses RTL-TCP on TCP 1234. A separate nftables
table restricts these ports to their respective configured clients, including
Docker's forwarded Beast traffic. Until clients are configured both ports
are blocked. Keep all devices on a private LAN; no router port forwards.
Changing reserved addresses requires updating this page.

Check services and reception after boot:

```bash
sudo systemctl status loft-firstboot loft-firewall loft-rtl-tcp adsb-setup
sudo journalctl -u loft-firstboot -u loft-firewall -u loft-rtl-tcp
sudo docker ps
```

The first-boot service is a prerequisite for receiver/application services:
invalid provisioning fails visibly rather than opening unauthenticated setup.
Upstream automatic application updates are disabled so they cannot overwrite
this integration. Install updates through reviewed new project releases.

## Optional 3.5-inch GPIO status display

Experimental MPI3501/LCD35-style ILI9486 profile, 480x320 landscape, SPI.
The LCDWiki pinout uses GPIO24 for data/command and GPIO25 for reset.
XPT2046 identifies only touch, so visually similar clones may still need
a different LCD driver. This profile does not enable touch or a fan.
Never attach/remove the GPIO display while the Pi is powered.
Use the pin-1 end of the Zero 2 W header and provide adequate power for
the display (approximately 0.16 A at 5 V) and two dongles.

On the existing v0.1.1 Pi image, SSH into the Pi and install the new support:

```bash
git clone --depth 1 https://github.com/matmat85/sdrhub.git ~/loft-sdr-source
sudo bash ~/loft-sdr-source/pi/display-install.sh --enable
sudo reboot
```

Future image builds include the files but leave the display disabled by
default. To enable them:

```bash
sudo bash /opt/loft-source/pi/display-install.sh --enable
sudo reboot
```

The independent `loft-display` service starts without waiting for Wi-Fi.
It shows boot/system state, uptime, Wi-Fi link state, LAN IPv4 addresses,
the setup URL, provisioning/web/RTL-TCP services and the ADS-B container
state, refreshing every five seconds. Wi-Fi connected means an associated
link, not verified Internet or LXC connectivity. Active radio/container
status does not prove incoming RF reception. No passwords are displayed.
There is no desktop, screen mirroring, automatic reboot or downloaded vendor
installer. The framebuffer is selected by its ILI9486 driver name, not
an assumed `/dev/fb1`; unsupported layouts fail visibly in the journal.

If blank or rotated incorrectly:

```bash
sudo journalctl -u loft-display -b
cat /sys/class/graphics/fb*/name
```

Change `rotate=90` to `rotate=270` in
`/boot/firmware/loft-display.txt` for the opposite landscape orientation,
then reboot. Do not use portrait rotation with this 480x320 dashboard.
If the framebuffer is missing, check the overlay/kernel logs rather than
running `LCD35-show`, which can replace unrelated boot settings.

Disable and restore the normal headless receiver:

```bash
sudo bash ~/loft-sdr-source/pi/display-install.sh --disable
sudo reboot
```

The script saves a timestamped `config.txt` backup before changing its
own include file. It does not alter radio or network settings. A display
failure does not prevent receiver services starting.
Rendering and status parsing are software-tested; actual display output
still requires testing on your board.

## Building the image

On a **dedicated native ARM64 Linux builder**, install curl, xz-utils, util-linux,
parted and e2fsprogs, then run `sudo bash pi/build.sh` from the repository.
The builder modifies only its newly created loop-mounted image, refuses an
existing image workspace, checks the official base image checksum, preserves
cloud-init and emits `dist/loft-pi.img.xz`. GitHub Actions uses
`ubuntu-24.04-arm` for this job.

An image build is not proof of successful physical boot. Test your Pi's USB
power, Wi-Fi bandwidth, antenna reception and real DAB audio before relying
on it. DAB needs approximately 32.8 Mbps plus overhead; wired networking may
be needed for reliable reception.
