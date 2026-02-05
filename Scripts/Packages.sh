#!/bin/bash
set -euo pipefail

# =========================================
# 单文件 OpenWrt 插件/软件包安装与更新脚本
# 包含: Docker / MBIM / NCM / RNDIS 支持
# =========================================

# ---------------------------
# 更新/安装第三方插件
# ---------------------------
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=${4:-}
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo -e "\n=== Processing $PKG_NAME ==="

	# 删除可能存在的旧目录
	for NAME in "${PKG_LIST[@]}"; do
		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Deleted: $DIR"
			done <<< "$FOUND_DIRS"
		fi
	done

	# 克隆仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	# 处理克隆结果
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf "./$REPO_NAME"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
}

# ---------------------------
# 更新软件包版本（GitHub Releases）
# ---------------------------
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	[ -z "$PKG_FILES" ] && return

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+" "$PKG_FILE")
		local PKG_TAG
		PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" \
			| jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		[ -z "$PKG_TAG" ] || [ "$PKG_TAG" == "null" ] && continue

		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/" "$PKG_FILE"
		sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/" "$PKG_FILE"

		echo "Updated $PKG_NAME -> $NEW_VER"
	done
}

# ---------------------------
# 安装官方 feeds 包（Docker / MBIM / NCM / RNDIS）
# ---------------------------
FEEDS_INSTALL() {
	echo -e "\n=== Installing feeds packages: $* ==="
	./scripts/feeds update -a
	./scripts/feeds install -a "$@"
}

# 官方 feeds 安装
FEEDS_INSTALL docker dockerd docker-compose luci-app-docker
FEEDS_INSTALL umbim kmod-usb-net-cdc-mbim luci-proto-mbim
FEEDS_INSTALL kmod-usb-net-cdc-ncm luci-proto-ncm
FEEDS_INSTALL kmod-usb-net-rndis luci-proto-rndis

# ---------------------------
# 第三方插件安装示例
# ---------------------------
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"

UPDATE_PACKAGE "homeproxy" "VIKINGYFY/homeproxy" "main"
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "diskman" "lisaac/luci-app-diskman" "master"
UPDATE_PACKAGE "fancontrol" "rockjake/luci-app-fancontrol" "main"

# ---------------------------
# 更新版本示例
# ---------------------------
UPDATE_VERSION "sing-box"
UPDATE_VERSION "tailscale"

echo -e "\n=== All tasks completed ✅ ==="
