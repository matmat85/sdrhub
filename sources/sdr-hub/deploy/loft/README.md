# Loft receivers with Proxmox LXC

For the flashable Pi image, first-boot Wi-Fi/account provisioning and automated
two-LXC installer, see the distribution's [main guide](../../../../README.md)
and [Pi guide](../../../../pi/README.md). The manual services below are an
alternative to that image; do not run a second RTL-TCP service beside the
image's `loft-rtl-tcp` service. This distribution's scanner build deliberately
omits the proprietary SDRplay SDK and targets RTL-SDR/RTL-TCP.

This fork keeps both USB radios on the Raspberry Pi Zero 2 W:

- `00000001`: the Pi decodes 1090 MHz ADS-B and exports Beast messages on port 30005.
- `77465553`: the Pi runs RTL-TCP on port 1234; SDR Hub on the LXC tunes, scans and records it.
- The feeder application, maps and aggregator clients run on the LXC. Its existing remote Beast input is reused.

Raw ADS-B streaming is deliberately avoided. The scanner starts at 1.024 MS/s,
approximately **16.4 Mbps before TCP overhead**, instead of two raw SDR streams.
Wi-Fi performance still needs testing. No software change can guarantee reliable
reception on a congested loft Wi-Fi link. Only one client can use the RTL-TCP
radio at a time. USB-over-IP and USB passthrough are not used.

## 1. Prepare the LXC

Use an x86-64 Debian/Ubuntu LXC with systemd, at least 2 CPU cores and preferably
4 GB RAM. Allow substantially more disk space for builds and recordings (20 GB
is a starting point, not a storage limit). Docker must work inside the LXC;
enable Proxmox's nesting/keyctl features as required for your LXC configuration.
Do not make the LXC privileged merely to access SDRs: it needs no USB devices.
Do not install this on the Proxmox host itself.

Inside the LXC, install a current Docker Engine and Compose v2 following
<https://docs.docker.com/engine/install/>. Confirm `docker info` and
`docker compose version` work. The feeder's local installer also checks its
Python/Flask/requests/cryptography/git/usbutils dependencies and reports missing
distribution packages. On Ubuntu 24.04 the initial prerequisites are:

```bash
sudo apt-get update
sudo apt-get install -y git python3 python3-flask python3-requests python3-cryptography usbutils
```

Copy the **four sibling checkouts, including these edits**, to the LXC:

```text
loft/
  sdr-hub/
  rtl-sdr-scanner-cpp/
  sdr-monitor/
  adsb-feeder-image/
```

Cloning upstream again will not include these changes. Copying the directories
is sufficient; no GitHub publishing or committing is required.

## 2. Pi: release the second radio and enable RTL-TCP

Keep the existing ADS-B feeder installation initially; it already supplies the
lightweight ADS-B decoding function and exposes Beast output on port 30005.
In its SDR setup, leave serial `00000001` assigned to 1090. Disable the VDL2
assignment for `77465553`, apply, and confirm its decoder container stops.
Do not run two decoders against the same dongle.

Reserve a fixed LAN address for the Pi. Copy this directory to the Pi and run
these commands **on the Pi**, after installing `rtl-sdr` if `rtl_tcp` is missing:

```bash
sudo apt-get update
sudo apt-get install -y rtl-sdr
sudo install -m 0644 pi-radio.env.example /etc/default/loft-radios
sudo nano /etc/default/loft-radios
sudo install -m 0644 loft-rtl-tcp.service /etc/systemd/system/loft-rtl-tcp.service
sudo systemctl daemon-reload
sudo systemctl enable --now loft-rtl-tcp.service
sudo systemctl status loft-rtl-tcp.service --no-pager
sudo journalctl -u loft-rtl-tcp.service -n 50 --no-pager
```

Change `LOFT_BIND_ADDRESS` to the Pi's actual LAN address. Confirm logs identify
the second radio; the `-d` selector uses its serial, not its changing USB address.
If your model needs a newer RTL-SDR driver (notably RTL-SDR Blog V4), use its
supported driver rather than assuming your distribution package is sufficient.
Both bias tees remain off; the service does not enable either.

The example service uses root for USB access, without privileged containers.
Keep ports 1234 and 30005 accessible **only from the LXC/private LAN** using
your existing firewall. Neither protocol authenticates or encrypts clients.
Do not forward these ports through your router. Record/receive only signals you
are legally permitted to use.

## 3. Build and start SDR Hub in the LXC

From the parent of the four checkouts:

```bash
bash sdr-hub/deploy/loft/build.sh
cd sdr-hub/deploy/loft
cp .env.example .env
nano .env
mkdir -p data logs
# Initial setup only: never overwrite an existing data/config.json.
test ! -e data/config.json && cp config.example.json data/config.json
nano data/config.json
docker compose config --quiet
docker compose up -d
docker compose logs --tail 100 sdr-hub
```

Set `LXC_BIND_ADDRESS` to the LXC's LAN address and choose two unique non-empty
passwords. Set `device_args.rtltcp` to `PI_ADDRESS:1234`. Set your actual antenna
latitude/longitude/altitude and legal scan ranges; the example covers 144-146 MHz
and is not a claim about local band allocations or antenna suitability.

Open `http://LXC_ADDRESS:8000` and log in as `admin` with your chosen HTTP
password. Scanner settings retain the endpoint across saves. A remote address
can also be edited in the web UI even when that device is disconnected.
Discovery no longer has to find the receiver via broadcast or localhost.
The serial in the scanner JSON is a display identity: the Pi's `rtl_tcp -d`
option is what selects the actual USB radio.

The build script runs the C++ remote-argument regression tests before building
the application, builds the changed scanner, overlays the changed web UI onto
the upstream monitor base image, then builds SDR Hub and checks driver loading.
The RTL-TCP plugin is pinned to a source commit. For repeatable production
builds, also pin the upstream monitor base to an image digest with
`--build-arg SDR_MONITOR_BASE=shajen/sdr-monitor@sha256:...` in the monitor build.
Existing data and logs survive container recreation.

Additional focused checks (from the parent of the four checkouts):

```bash
bash sdr-hub/deploy/loft/tests/build.test.sh
bash sdr-hub/deploy/loft/tests/config.test.sh
bash sdr-hub/deploy/loft/tests/remote-smoke.test.sh
docker build -f adsb-feeder-image/tests/installer/Dockerfile \
  -t loft/feeder-installer-tests:local adsb-feeder-image
docker run --rm loft/feeder-installer-tests:local
```

The installer tests run in a disposable container, not against the LXC's live
systemd services or filesystem.
The remote smoke test uses a mock RTL-TCP server in an isolated Docker network,
checks tuning/sample-rate commands and restart recovery, and removes its test
containers afterward. It does not validate antennas or real RF reception.

## 4. Install the changed feeder application in the LXC

The feeder image is a distro/application manager, **not a single Docker image**.
Use its local-source installer; it runs the application under systemd and manages
its decoder/maps/aggregator Docker containers. On a **fresh LXC**:

```bash
cd /path/to/loft
sudo bash adsb-feeder-image/src/tools/app-install.sh -l "$PWD/adsb-feeder-image"
```

This installs the downloaded, edited checkout, instead of cloning upstream and
losing changes. The installer leaves the local checkout untouched. Do not rerun
it over a configured installation without a backup: upstream install behavior
appends initial settings to `.env`.

Open `http://LXC_ADDRESS:1099`. Configure the actual antenna location, not the
location of the Proxmox server. On SDR setup:

- Leave local 1090 SDR assignments empty.
- Enter `PI_ADDRESS,30005` in the existing **remote device / beast_out** field.
- Apply and verify the aircraft map at `http://LXC_ADDRESS:1090` shows live data.
- Configure your chosen aggregators in the feeder UI.

Only after the LXC is working, use the Pi's **Setup** page to select **ADS-B >
Nano** and apply. Nano is the lowest-memory upstream receiver mode and disables
local feeding/graphs; **Micro** is an alternative if you want more local features.
Both retain Beast output on port 30005. Back up site identifiers/UUIDs before
migrating aggregator identities, and confirm aggregator clients are not running
twice.
Do not disable or stop the Pi's 1090 decoder itself: the LXC still needs its
Beast output. The Pi may keep a minimal status/map service depending on the
upstream micro-feeder configuration.

Upstream UI updates can replace the custom installed feeder files. Back up
configuration and reapply local changes before enabling upstream updates. The
LXC uses the default integrated feeder mode with a remote SDR input; Stage 2 is
not required for this single remote ADS-B receiver.

## 5. Verify the actual outcome

### Live FM and DAB/DAB+

Open **Listen to live FM / DAB radio** on the SDR Hub home page, or
`http://LXC_ADDRESS:8000/sdr/radio/`. This page requires a staff login. Choose
FM and a frequency in MHz (87.5-108), or DAB and a Band III multiplex channel.
Click **Tune radio**, then Play on the audio control. DAB/DAB+ decoding uses
the packaged welle-cli; wait for service discovery and click **Refresh station
list** to see programmes on that multiplex.

Radio mode stops the scanner before opening RTL-TCP. **Resume scanning** stops
the player and restarts scanning. Closing the browser does not resume scanning:
use the button. Radio mode is shared by all users of this SDR Hub instance.
One live FM listener is supported at a time; pause other players before playing.
The configured display serial defaults to `77465553`; set `SDR_RADIO_SERIAL`
in the container environment only if intentionally using a different scanner.
This does not change the Pi's serial selection. No ADS-B container is controlled.

FM audio is mono MP3 at 32 kHz with GNU Radio's 75 microsecond de-emphasis
(stereo and regional 50 microsecond de-emphasis are not implemented). DAB
requires 2.048 MS/s, roughly 32.8 Mbps plus overhead. Reception needs a Band III
antenna and uninterrupted Wi-Fi; a build or mock test cannot establish DAB RF
coverage. Do not expect FM/DAB and scanning simultaneously with this dongle.
Container restarts return to scanning, rather than restoring an old radio mode.
Errors are shown on the page and in `radio_player.log`. MP3 streams are gated
by Django authentication; the internal audio proxy and supervisor control ports
are not published outside the container.

Focused radio controller tests:

```bash
docker run --rm --entrypoint python3 -e PYTHONPATH=/app -w /app \
  -v "$PWD/sdr-monitor/tests/radio.test.py:/radio.test.py:ro" \
  loft/sdr-hub:local /radio.test.py
```

The remote smoke test also checks authenticated FM MP3 output contains a
synthetic 1 kHz FM-modulated tone, actual welle-cli
startup and multiplex JSON, and returning to scanning. A mock RTL-TCP stream
does not contain a real DAB multiplex: listening to DAB/DAB+ audio still needs
verification with your antenna and a local broadcast.

On the LXC:

```bash
curl -I http://LXC_ADDRESS:8000/
docker compose -f sdr-hub/deploy/loft/compose.yml \
  --env-file sdr-hub/deploy/loft/.env logs --tail 100 sdr-hub
docker stats --no-stream
```

Check scanner logs for `rtltcp` and `77465553`, a 1.024 MHz sample rate, and actual
recordings/spectrograms. Check the feeder's live ADS-B message rate and map while
scanning. Disconnect/reconnect the Pi's Wi-Fi briefly: a missing remote scanner
is retried every 10 seconds; a stream error causes supervisor to restart the
scanner. Check both applications recover, and verify again after rebooting the
Pi and LXC. Do not claim RF operation is validated from a successful image build.

If ADS-B message rates drop, reduce scanning workload, move the Wi-Fi access
point, or use Ethernet. Monitor SD/disk usage and set recording retention using
the existing SDR Hub settings. Multi-band scanning hops between bands; it is
not continuous reception of all bands simultaneously.

For rollback, stop SDR Hub on the LXC, disable `loft-rtl-tcp` on the Pi, and
reassign `77465553` to VDL2 if desired. Re-enable the Pi's original feeding
configuration if moving aggregators back. No SDR serials are rewritten.
