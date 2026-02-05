#!/bin/bash

# ===============================
# 安装和更新第三方软件包
# ===============================
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" \
			-prune -exec cp -rf {} ./ \;
		rm -rf ./"$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# ===============================
# 第三方插件列表
# ===============================
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
# UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "luci-app-timewol luci-app-wolplus"

# ===============================
# 官方 feeds 安装（Docker / MBIM / NCM / RNDIS）
# ===============================
FEEDS_INSTALL() {
	echo " "
	echo "===== Install official feeds packages ====="
	./scripts/feeds update -a
	./scripts/feeds install -a "$@"
}

FEEDS_INSTALL \
	docker dockerd docker-compose luci-app-docker \
	umbim kmod-usb-net-cdc-mbim luci-proto-mbim \
	kmod-usb-net-cdc-ncm kmod-usb-net-rndis

# ===============================
# 自动检测 USB 网络类型 + 信号显示
# ===============================
USB_NET_MONITOR() {
	echo
	echo "===== USB Network Detection ====="

	for iface in $(ls /sys/class/net/ | grep -E "wwan|usb|eth"); do
		type="unknown"
		signal="N/A"

		# 判断类型
		if [[ -d "/sys/class/net/$iface/device/driver" ]]; then
			drv=$(basename $(readlink /sys/class/net/$iface/device/driver))
			case "$drv" in
				cdc_mbim) type="MBIM" ;;
				cdc_ncm)  type="NCM" ;;
				rndis_host) type="RNDIS" ;;
			esac
		fi

		# 获取 MBIM 信号强度
		if [[ "$type" == "MBIM" ]]; then
			dev=$(basename $(readlink /sys/class/net/$iface/device))
			if [[ -c "/dev/$dev" ]]; then
				signal=$(mbimcli -d "/dev/$dev" --query-signal | grep -Po 'RSSI\s*:\s*\K[0-9\-]+')
			fi
		fi

		echo "Interface: $iface | Type: $type | Signal: $signal"
	done
}

# 启动检测
USB_NET_MONITOR

# ===============================
# 软件包版本更新
# ===============================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	[ -z "$PKG_FILES" ] && return

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+" "$PKG_FILE")
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" \
			| jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		[ -z "$PKG_TAG" ] && continue

		local NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/" "$PKG_FILE"
		sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/" "$PKG_FILE"
	done
}

UPDATE_VERSION "sing-box"
UPDATE_VERSION "tailscale"
