#
# Copyright (C) 2006-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=multiwan-nft
PKG_VERSION:=1.1.17
PKG_RELEASE:=1
PKG_MAINTAINER:=Florian Eckert <fe@dev.tdt.de>, \
		Aaron Goodman <aaronjg@alumni.stanford.edu>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/multiwan-nft
   SECTION:=net
   CATEGORY:=Network
   SUBMENU:=Routing and Redirection
   PKGARCH:=all
   DEPENDS:= \
     +ip-full \
     +nftables-json \
     +kmod-nft-fib \
     +jshn \
     +rpcd \
     +conntrack \
     +multiwan-nft-sockopt
   TITLE:=MultiWAN NFT multi-WAN manager
   MAINTAINER:=Florian Eckert <fe@dev.tdt.de>
   PROVIDES:=mwan3
   CONFLICTS:=mwan3
   REPLACES:=mwan3
endef

define Package/multiwan-nft/description
NFT-native multi-WAN routing manager with load balancing, failover,
connection tracking, and LuCI/rpcd integration.

The routing scripts are architecture-independent. The required target-built
socket helper binds generic commands and DNS probes to the selected WAN.
endef

define Package/multiwan-nft-sockopt
   SECTION:=net
   CATEGORY:=Network
   SUBMENU:=Routing and Redirection
   TITLE:=MultiWAN socket binding helper
   DEPENDS:=+libc +libgcc
endef

define Package/multiwan-nft-sockopt/description
Target-built socket binding for MultiWAN NFT tracking and the use command.
Supports dynamically linked programs, matching upstream mwan3's binding model.
endef

define Package/multiwan-nft/conffiles
/etc/config/multiwan-nft
/etc/multiwan-nft.user
endef

define Package/multiwan-nft/preinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -f /lib/multiwan-nft/multiwan_nft.sh ]; then
	(umask 077; : > /var/run/multiwan-nft-upgrade-pending) || exit 1
fi
exit 0
endef

define Package/multiwan-nft/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload
endef

define Package/multiwan-nft/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) ./src/sockopt_wrap.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -std=gnu11 -fPIC -shared \
		$(TARGET_LDFLAGS) -Wl,-soname,libwrap_mwan3_sockopt.so.1 \
		-o $(PKG_BUILD_DIR)/libwrap_mwan3_sockopt.so.1.0 \
		$(PKG_BUILD_DIR)/sockopt_wrap.c -ldl
endef

define Package/multiwan-nft-sockopt/install
	$(INSTALL_DIR) $(1)/lib/multiwan-nft
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/libwrap_mwan3_sockopt.so.1.0 \
		$(1)/lib/multiwan-nft/
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

$(eval $(call BuildPackage,multiwan-nft-sockopt))
$(eval $(call BuildPackage,multiwan-nft))
