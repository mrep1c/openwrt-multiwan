#
# Copyright (C) 2006-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=multiwan-nft
PKG_VERSION:=1.0.3
PKG_RELEASE:=1
PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>, \
		Aaron Goodman <aaronjg@alumni.stanford.edu>
PKG_LICENSE:=GPL-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/multiwan-nft
   SECTION:=net
   CATEGORY:=Network
   SUBMENU:=Routing and Redirection
   PKGARCH:=all
   DEPENDS:= \
     +ip-full \
     +nftables \
     +jshn \
     +rpcd \
     +conntrack
   TITLE:=MultiWAN NFT multi-WAN manager
   MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
   PROVIDES:=mwan3
   CONFLICTS:=mwan3
   REPLACES:=mwan3
endef

define Package/multiwan-nft/description
NFT-native multi-WAN routing manager with load balancing, failover,
connection tracking, and LuCI/rpcd integration.

This package is architecture-independent and uses native interface binding
when the optional sockopt wrapper library is not installed.
endef

define Package/multiwan-nft/conffiles
/etc/config/multiwan-nft
/etc/multiwan-nft.user
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/multiwan-nft/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/multiwan-nft \
		$(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./files/etc/hotplug.d/iface/15-multiwan-nft \
		$(1)/etc/hotplug.d/iface/
	$(INSTALL_DATA) ./files/etc/hotplug.d/iface/16-multiwan-nft-user \
		$(1)/etc/hotplug.d/iface/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/multiwan-nft \
		$(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/lib/multiwan-nft
	$(INSTALL_DATA) ./files/lib/multiwan-nft/common.sh \
		$(1)/lib/multiwan-nft/
	$(INSTALL_DATA) ./files/lib/multiwan-nft/multiwan_nft.sh \
		$(1)/lib/multiwan-nft/
	$(INSTALL_DATA) ./files/lib/multiwan-nft/process-lock.sh \
		$(1)/lib/multiwan-nft/

	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/multiwan_nft \
		$(1)/usr/libexec/rpcd/

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/multiwan-nft \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/multiwan-nft-rtmon \
		$(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/sbin/multiwan-nft-track \
		$(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_BIN) ./files/etc/multiwan-nft.user \
		$(1)/etc/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/10-multiwan-nft-migrate-config \
		$(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./files/etc/uci-defaults/multiwan-nft-migrate-flush_conntrack \
		$(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,multiwan-nft))
