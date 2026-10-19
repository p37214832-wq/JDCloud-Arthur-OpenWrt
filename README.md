# JDCloud Arthur (RE-SS-01) OpenWrt Firmware Build

*** JDCloud RE-SS-01 ONLY - do NOT use for ZN-M2 / Cudy TR3000 / newifi D2 ***

Cloud build for JDCloud RE-SS-01 (AX1800 Pro, Qualcomm IPQ60xx, eMMC).

## Device
- **Model**: JDCloud RE-SS-01 (AX1800 Pro)
- **Target**: qualcommax/ipq60xx/jdcloud_re-ss-01
- **Flash**: eMMC (images: factory.bin + sysupgrade.bin, NOT .ubi)
- **Ports**: lan1 / lan2 / lan3 / wan
- **RAM**: 1GB | **Swap**: 512MB + 256MB zram | **Disk**: ~111GB (mmcblk0p27)

## Features
- daede (kenzok8): dae + luci-app-daede (no daed backend)
- tailscale (OFF by default, firewall ACCEPT rules pre-installed)
- ttyd + luci-app-ttyd
- Docker (dockerd + compose + dockerman), data dir /opt/docker
- luci-app-diskman (111GB disk management)
- Samba4, DDNS, UPnP (all enabled)
- zram-swap, htop
- NSS: nss-drv + nss-dp (ECM DISABLED)

## Build
Push to `main` or run workflow manually. Firmware appears under Releases.

## Design doc
`~/workspace/your_files/jdcloud-arthur-firmware-design/jdcloud-arthur-firmware-design.pdf`
