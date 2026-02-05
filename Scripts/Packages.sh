#!/bin/bash
set -euo pipefail

# =========================
# 配置区域（可自定义）
# =========================
WRT_THEME="argon"               # 默认主题
WRT_SSID="MyWiFi"               # 默认WIFI名
WRT_WORD="12345678"             # 默认WIFI密码
WRT_IP="192.168.125.1"           # 默认LAN IP
WRT_NAME="OpenWrt"              # 主机名
WRT_MARK="CUSTOM"               # 版本标识
WRT_DATE=$(date +%Y%m%d)        # 编译日期
WRT_PACKAGE=""                  # 手动添加的插件
WRT_TARGET="qualcommax"         # 平台
WRT_CONFIG="ipq60xx-wifi"       # 机型配置

# =========================
# 安装和更新插件函数
# =========================
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=${4:-""}
	local PKG_LIST=("$PKG_NAME" "${5:-}")  # 修复未定义 $5
	local REPO_NAME=${PKG_REPO#*/}

	echo " "
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		fi
	done

	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./"$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# =========================
# 插件列表
# =========================
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"

# 选择是否加 OpenClash
#UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
#UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"

# =========================
# 官方 feeds 包（Docker/MBIM/NCM/RNDIS）
# =========================
./scripts/feeds update -a
./scripts/feeds install -a \
	docker dockerd docker-compose luci-app-docker \
	umbim kmod-usb-net-cdc-mbim luci-proto-mbim \
	kmod-usb-net-cdc-ncm kmod-usb-net-rndis

# =========================
# 更新软件包版本（可选）
# =========================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")
	[ -z "$PKG_FILES" ] && return
	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+" "$PKG_FILE")
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		[ -z "$PKG_TAG" ] && continue
		local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/" "$PKG_FILE"
		sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/" "$PKG_FILE"
	done
}
UPDATE_VERSION "sing-box"
UPDATE_VERSION "tailscale"

# =========================
# 自动生成 .config
# =========================
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

# 增加 USB 支持
echo "CONFIG_PACKAGE_kmod-usb-core=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb2=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb3=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-serial=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y" >> ./.config
echo "CONFIG_PACKAGE_kmod-usb-net-rndis=y" >> ./.config

# =========================
# 编译
# =========================
echo "Start compiling OpenWrt..."
make defconfig
make -j$(nproc)

echo "✅ 编译完成，刷机文件在 bin/targets/ 下"
