# Loft SDR Hub

Two RTL-SDR receivers on a Raspberry Pi Zero 2 W, with ADS-B and SDR Hub
running in separate Docker-enabled Proxmox LXCs.

## Status

Development source, not a ready-to-flash release. Remote SDR support and the
FM/DAB interface have been built and exercised with network/audio integration
tests. A custom Pi image, first-boot provisioning, Pi setup UI extensions and
release automation are still unfinished. The Proxmox installer is experimental:
do not run it until a tested release and its required assets are published.

No Pi image or production-ready one-line installer is currently available.
Physical Pi boot, real DAB audio and deployment on Proxmox remain unverified.

## Architecture

| Location | Function |
| --- | --- |
| Loft Pi, serial `00000001` | Decode 1090 MHz ADS-B locally; export Beast on TCP 30005 |
| Loft Pi, serial `77465553` | Stream RTL-TCP samples on TCP 1234 |
| ADS-B LXC | Existing feeder remote Beast input, maps and aggregator configuration |
| SDR Hub LXC | Remote scanning plus authenticated live FM/DAB controls |

The scanner and radio player share the second receiver exclusively. FM is
currently mono, without RDS. DAB service selection uses welle-cli. Select
**Resume scanning** when finished listening.

Raw samples require approximately 16.4 Mbps for scanning/FM and 32.8 Mbps for
DAB before network overhead. Pi Zero 2 W Wi-Fi may not sustain DAB reliably.
Beast and RTL-TCP are not authenticated or encrypted: keep them on a private
LAN and restrict access to the intended LXC addresses. Do not port-forward them.

## Build and manual setup

The edited upstream sources, including licenses and tests, are in
[sources](sources). The inherited scanner Dockerfile also requires
`SDRplay_RSP_API-Linux-3.15.2.run` in
`sources/rtl-sdr-scanner-cpp/sdrplay/`. This proprietary SDK is intentionally
not redistributed here; obtain it from SDRplay under their license before
using the current Dockerfile. Removing that unnecessary dependency for our
RTL-SDR-only release is still pending.

On Linux with Docker installed and that build prerequisite available:

```bash
bash sources/sdr-hub/deploy/loft/build.sh
```

This builds the scanner, monitor overlay and combined `loft/sdr-hub:local`
image, and runs the scanner's device-argument regression tests.

Follow the [manual deployment guide](sources/sdr-hub/deploy/loft/README.md)
for Pi services, remote Beast configuration, Docker Compose setup and radio
controls. It also documents the focused UI and network/audio tests.
Do not use real passwords or Wi-Fi credentials in committed configuration.

## Sources and licensing

This project combines modified GPLv3 upstream projects:

- [shajen/sdr-hub](https://github.com/shajen/sdr-hub)
- [shajen/sdr-monitor](https://github.com/shajen/sdr-monitor)
- [shajen/rtl-sdr-scanner-cpp](https://github.com/shajen/rtl-sdr-scanner-cpp)
- [dirkhh/adsb-feeder-image](https://github.com/dirkhh/adsb-feeder-image)

Original license texts and notices are retained in each source directory.
Integration code is provided under GPLv3; see
[the GPLv3 license](sources/sdr-hub/LICENSE). Other bundled components retain
their respective license notices. [upstreams.lock](upstreams.lock) records
the upstream revisions used before local modifications.
