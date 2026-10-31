# Loft SDR Hub

Two RTL-SDR receivers on a Raspberry Pi Zero 2 W, with ADS-B and SDR Hub
running in separate Docker-enabled Proxmox LXCs.

## Status

The repository includes a native ARM64 Pi image builder, first-boot provisioning,
authenticated receiver setup, a source-only SDR Hub Docker build and a Proxmox
installer. GitHub Actions builds and tests both image artifacts and publishes
tagged prereleases with checksums. Check the latest workflow result before
downloading a release.

Physical Pi boot, real DAB audio and actual Proxmox installation remain
unverified. Releases are explicitly marked prerelease until hardware testing.

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
[sources](sources). The scanner and combined hub no longer depend on the
proprietary SDRplay SDK: this distribution targets RTL-SDR/RTL-TCP, not SDRplay.
On Linux with Docker installed:

```bash
bash sources/sdr-hub/deploy/loft/build.sh
```

This builds the scanner, monitor overlay and combined `loft/sdr-hub:local`
image, and runs the scanner's device-argument regression tests.

## Install a built release

1. Flash the Pi image and configure Wi-Fi, your OS account and both radios
   using the [Pi setup guide](pi/README.md).
2. On a Proxmox VE 9 **host** as root, download and inspect the release installer:

   ```bash
   curl -fL https://github.com/matmat85/sdrhub/releases/download/v0.1.0/proxmox.sh -o /root/loft-proxmox.sh
   less /root/loft-proxmox.sh
   bash /root/loft-proxmox.sh
   ```

   It prompts for the Pi address, storage, bridge and two fresh CT IDs, then
   requires explicit `CREATE` confirmation. It creates two unprivileged Debian
   13 LXCs with nesting enabled, downloads checksum-verified source and Docker
   image archives, installs software and prints unique login credentials.
   No GitHub/registry account is required. Existing CTs/VMs are not overwritten.
   Failed new CTs are retained for diagnosis, not automatically destroyed.

3. Reserve both LXC DHCP addresses. Update the Pi receiver page with those
   addresses so its firewall permits their connections.
4. Finish location and aggregator setup on the ADS-B LXC. Remote Beast input
   is already configured. On SDR Hub, set location and legal scan ranges;
   **Live radio** provides FM/DAB tuning, listening and resume-scanning controls.

The distribution is one flashable Pi image plus two LXC installations, not
three interchangeable OS images. Docker runs only inside LXCs, never directly
on the Proxmox host. The release includes a compressed Docker image archive so
installation does not depend on private GHCR package visibility.

## Validation and releases

After building the hub, run `bash scripts/test.sh` with Docker and ShellCheck.
It checks both feeder installation modes, receiver authentication/CSRF and
exclusive serial assignments, Proxmox command generation/checksum rejection,
remote-device UI regression and live network/FM/DAB-decoder integration.
The ARM image job checks the official Raspberry Pi OS base checksum.

Use **Actions -> Build loft receiver release -> Run workflow** for development
artifacts. A version tag such as `v0.1.0` publishes the complete release only
after both build jobs succeed. Release assets include `loft-pi.img.xz`,
`pi-imager.json`, `hub-image.tar.gz`, `hub-image.txt`, `sdrhub-source.tar.gz`,
`proxmox.sh` and `SHA256SUMS`.

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
