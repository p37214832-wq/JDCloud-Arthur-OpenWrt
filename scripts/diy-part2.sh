#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# JDCloud Arthur (RE-SS-01) - based on ZN-M2 v4 (verified 2026-10-17)
# *** JDCloud RE-SS-01 ONLY - do NOT use for ZN-M2 / Cudy / newifi ***
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: Customizing VIKINGYFY/ImmortalWrt"
echo "             JDCloud Arthur (RE-SS-01)"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. WiFi: KEEP (IPQ6000 on-chip AHB WiFi, same as ZN-M2)
echo "[1/4] Verifying WiFi packages in DEFAULT_PACKAGES..."
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"
echo "  -> WiFi packages:"
grep -o "wpad-openssl\|kmod-ath11k-ahb\|kmod-ath11k-pci\|kmod-ath11k" "$TARGET_MAKEFILE" 2>/dev/null | sort -u || echo "  -> WARNING: WiFi packages not found!"

# 2. Add daede packages (kenzok8 edition, actively maintained).
# Same verified combo as ZN-M2 v4: dae 2026.09.30 + luci-app-daede 1.15.
# Must land in package/ BEFORE `make defconfig` so CONFIG_PACKAGE_* resolves.
echo "[2/4] Installing daede (kenzok8 edition)..."
rm -rf package/dae package/daed package/luci-app-dae package/luci-app-daede
find feeds package/feeds -maxdepth 4 \( -name "dae" -o -name "daed" -o -name "luci-app-dae" -o -name "luci-app-daede" \) 2>/dev/null | while read -r d; do
    echo "  -> removing existing copy: $d"
    rm -rf "$d"
done
git clone --depth 1 https://github.com/kenzok8/openwrt-daede.git /tmp/daede-src
# Copy all three so luci-app-daede's Makefile can reference ../daed/files/daed.config
# (it hardcodes the sibling path). Only dae + luci-app-daede are selected in
# .config; daed backend is NOT built (saves memory).
for pkg in dae daed luci-app-daede; do
    if [ -d "/tmp/daede-src/$pkg" ]; then
        cp -r "/tmp/daede-src/$pkg" "package/$pkg"
        echo "  -> $pkg (kenzok8) installed to package/"
    else
        echo "  -> ERROR: $pkg not found in kenzok8/openwrt-daede!"
        exit 1
    fi
done
rm -rf /tmp/daede-src
# NOTE: daed backend copied for Makefile reference only, NOT selected in .config

# 2b. Slim the dae package: install ONLY the main `dae` binary.
# GoPackage/Package/Install/Bin would also ship build-time helper tools
# (~13.7MB). Tolerant: warn and continue if the install line is not found.
python3 - <<'PYEOF'
p = 'package/dae/Makefile'
s = open(p).read()
old = "\t$(call GoPackage/Package/Install/Bin,$(1))\n"
add = ("\t# keep only the main dae binary; drop build-time helper tools (~13.7MB)\n"
       "\tfor f in $(1)/usr/bin/*; do \\\n"
       "\t\t[ \"$$f\" = \"$(1)/usr/bin/dae\" ] || rm -f \"$$f\"; \\\n"
       "\tdone\n")
if old not in s:
    print("  -> WARNING: GoPackage install line not found, dae NOT slimmed!")
else:
    open(p, 'w').write(s.replace(old, old + add, 1))
    print("  -> dae install slimmed to main binary only")
PYEOF

# 2c. tailscale vs luci-app-tailscale file conflict: both ship
# etc/config/tailscale and etc/init.d/tailscale, which fails image assembly.
# Strip the duplicates from the luci app (tolerant if paths differ or gone).
if [ -d "feeds/luci/applications/luci-app-tailscale" ]; then
    find feeds/luci/applications/luci-app-tailscale -path "*etc/config/tailscale" -delete 2>/dev/null || true
    find feeds/luci/applications/luci-app-tailscale -path "*etc/init.d/tailscale" -delete 2>/dev/null || true
    echo "  -> stripped tailscale file conflicts from luci-app-tailscale"
fi

# 3. Verify device + key packages
echo "[3/4] Final verification..."
echo ""
echo "  -> RE-SS-01 device definition (MUST exist):"
IPQ60XX_IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
if grep -q "define Device/jdcloud_re-ss-01" "$IPQ60XX_IMAGE_MK" 2>/dev/null; then
    echo "    [OK] jdcloud_re-ss-01 found in ipq60xx.mk"
    grep -A6 "define Device/jdcloud_re-ss-01" "$IPQ60XX_IMAGE_MK" | head -8
else
    echo "    [ERROR] jdcloud_re-ss-01 NOT found in ipq60xx.mk - wrong source or device removed!"
    exit 1
fi
echo ""
echo "  -> RE-SS-01 DTS:"
ls target/linux/qualcommax/dts/ipq6000-re-ss-01.dts 2>/dev/null && echo "    [OK]" || echo "    [WARN] ipq6000-re-ss-01.dts NOT found!"
echo ""
echo "  -> NSS stack:"
for pkg in qca-nss-drv qca-nss-dp qca-ssdk nss-firmware; do
    if [ -d "package/qca-nss/$pkg" ]; then
        echo "    [OK] package/qca-nss/$pkg"
    else
        echo "    [WARN] package/qca-nss/$pkg NOT found!"
    fi
done
echo ""
echo "  -> Key packages:"
for pkg in dae luci-app-daede ttyd luci-app-ttyd tailscale dockerd luci-app-dockerman luci-app-diskman luci-app-samba4 luci-app-ddns luci-app-upnp; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "    [OK] $pkg"
    else
        echo "    [WARN] $pkg NOT found!"
    fi
done
# luci-app-tailscale: ZN-M2 v4 lesson - may be missing from feeds, warn only
if find feeds/ -path "*luci-app-tailscale/Makefile" 2>/dev/null | head -1 | grep -q .; then
    echo "    [OK] luci-app-tailscale (LuCI page will be included)"
else
    echo "    [WARN] luci-app-tailscale NOT in feeds - .config entry will be dropped,"
    echo "           tailscale CLI still works (same as ZN-M2 v4)"
fi

# 4. files/ overlay: CN mirrors + first-boot defaults
echo ""
echo "[4/4] Setting up files overlay..."
mkdir -p files/etc/opkg files/etc/uci-defaults files/etc/crontabs files/opt/docker

# Chinese opkg mirrors (Tsinghua) - same ipq60xx target path as ZN-M2
cat > files/etc/opkg/distfeeds.conf << 'FEEDSEOF'
src/gz openwrt_core https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/targets/qualcommax/ipq60xx/packages
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony
FEEDSEOF
echo "  -> files/etc/opkg/distfeeds.conf (Tsinghua mirrors)"

# First-boot defaults: open WiFi, tailscale OFF, conntrack 32768 (1GB RAM),
# Tailscale firewall ACCEPT rules (ZN-M2 v4 lesson: explicit rules, not zone)
cat > files/etc/uci-defaults/99-jdcloud-arthur << 'UCIEOF'
#!/bin/sh
# JDCloud Arthur (RE-SS-01) first-boot defaults
# LAN stays 192.168.1.1 default (user changes manually; presetting breaks networking - ZN-M2 lesson)

# Open WiFi (user sets password later)
uci set wireless.@wifi-iface[0].encryption='none' 2>/dev/null
uci delete wireless.@wifi-iface[0].key 2>/dev/null
uci set wireless.@wifi-iface[1].encryption='none' 2>/dev/null
uci delete wireless.@wifi-iface[1].key 2>/dev/null
uci commit wireless 2>/dev/null

# tailscale OFF by default (user enables via /etc/init.d/tailscale enable when needed)
/etc/init.d/tailscale disable 2>/dev/null || true

# conntrack max for 1GB RAM
echo "32768" > /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || true
mkdir -p /etc/sysctl.d
echo "net.netfilter.nf_conntrack_max=32768" > /etc/sysctl.d/99-jdcloud-arthur.conf

# Tailscale firewall: explicit ACCEPT rules (ZN-M2 v4 lesson 2026-10-17:
# nftables/fw4 zone membership for dynamic tailscale0 is unreliable)
# Allow Tailscale -> LuCI (TCP 80) and daede standalone UI (TCP 2023)
uci add firewall rule 2>/dev/null
uci set firewall.@rule[-1].name='Allow-Tailscale-HTTP' 2>/dev/null
uci set firewall.@rule[-1].src='*' 2>/dev/null
uci set firewall.@rule[-1].dest_port='80' 2>/dev/null
uci set firewall.@rule[-1].proto='tcp' 2>/dev/null
uci set firewall.@rule[-1].target='ACCEPT' 2>/dev/null
uci add firewall rule 2>/dev/null
uci set firewall.@rule[-1].name='Allow-Tailscale-Daede' 2>/dev/null
uci set firewall.@rule[-1].src='*' 2>/dev/null
uci set firewall.@rule[-1].dest_port='2023' 2>/dev/null
uci set firewall.@rule[-1].proto='tcp' 2>/dev/null
uci set firewall.@rule[-1].target='ACCEPT' 2>/dev/null
uci commit firewall 2>/dev/null

# Docker data dir (on 111GB partition after user sets it up per design doc section 3)
mkdir -p /opt/docker

exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-jdcloud-arthur
echo "  -> files/etc/uci-defaults/99-jdcloud-arthur (open WiFi, tailscale OFF, conntrack 32768, Tailscale fw rules)"

# Scheduled tasks: user sets times manually (confirmed 2026-10-19).
# Preset as COMMENTED entries - user uncomments and sets time in LuCI.
cat > files/etc/crontabs/root << 'CRONEOF'
# JDCloud Arthur scheduled tasks (all disabled by default - user sets times)
# Uncomment and adjust the time, then /etc/init.d/cron restart
#
# Weekly full reboot (example: Sunday 04:00)
#0 4 * * 0 sleep 5 && touch /etc/banner && reboot
#
# Weekly dae restart (example: Wednesday 04:00, off-peak from full reboot)
#0 4 * * 3 /etc/init.d/dae restart
#
# Drop caches every 6 hours
#0 */6 * * * sync && echo 3 > /proc/sys/vm/drop_caches
CRONEOF
echo "  -> files/etc/crontabs/root (all commented - user sets times manually)"

echo ""
echo "============================================"
echo " Build Summary - JDCloud Arthur (RE-SS-01)"
echo "============================================"
echo " Source:  VIKINGYFY/ImmortalWrt main (NSS Full Support)"
echo " Kernel:  6.18 + eBPF/BTF (required by dae)"
echo " Target:  qualcommax/ipq60xx/jdcloud_re-ss-01 (eMMC)"
echo " Images:  factory.bin + sysupgrade.bin (NOT .ubi - eMMC device)"
echo " Ports:   lan1 / lan2 / lan3 / wan"
echo " NSS:     nss-drv + nss-dp + ssdk + firmware (ECM DISABLED)"
echo " Features: daede (kenzok8, dae + luci-app-daede, no daed backend)"
echo "           + tailscale (OFF by default, fw rules pre-installed)"
echo "           + ttyd + luci-app-ttyd"
echo "           + dockerd + docker-compose + luci-app-dockerman"
echo "           + luci-app-diskman (111GB disk management)"
echo "           + samba4 + ddns + upnp (user confirmed all 5)"
echo "           + zram-swap (256MB) + htop"
echo " Cron:    all commented - user sets times in LuCI"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
