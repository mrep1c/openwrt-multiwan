#
# Copyright (C) 2017 Dan Luedtke <mail@danrl.com>
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for MultiWAN NFT
LUCI_DEPENDS:=+luci-base +multiwan-nft
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-multiwan-nft
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_PO_VERSION:=1.0.0-r1
PKG_PROVIDES:=luci-app-mwan3
PKG_CONFLICTS:=luci-app-mwan3
PKG_REPLACES:=luci-app-mwan3
PKG_LICENSE:=GPL-2.0

PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
