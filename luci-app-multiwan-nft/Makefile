#
# Copyright (C) 2017 Dan Luedtke <mail@danrl.com>
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for MultiWAN NFT
LUCI_DEPENDS:=+luci-base +multiwan-nft
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-multiwan-nft
PKG_VERSION:=1.1.17
PKG_RELEASE:=1
PKG_PO_VERSION:=1.1.17-r1
PKG_PROVIDES:=luci-app-mwan3
PKG_CONFLICTS:=luci-app-mwan3
PKG_REPLACES:=luci-app-mwan3
PKG_LICENSE:=GPL-2.0

PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>

define Build/Prepare/luci-app-multiwan-nft
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/libexec/luci-multiwan-nft
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
