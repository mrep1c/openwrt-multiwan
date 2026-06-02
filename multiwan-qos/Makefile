include $(TOPDIR)/rules.mk

PKG_NAME:=multiwan-qos
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Markus Hütter <mh@hudra.net>
PKG_LICENSE:=GPL-3.0-or-later
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/multiwan-qos
  SECTION:=net
  CATEGORY:=Base system
  PKGARCH:=all
  TITLE:=MultiWAN QoS - Quality of Service management tool
  DEPENDS:=+kmod-sched +ip-full +nftables +kmod-veth +tc-full +kmod-netem +kmod-sched-ctinfo +kmod-ifb +kmod-sched-cake +kmod-sched-red +kmod-sched-flower +lua +luci-lib-jsonc +jsonfilter +uclient-fetch
  PROVIDES:=qosmate
  CONFLICTS:=qosmate
  REPLACES:=qosmate
endef

define Package/multiwan-qos/description
  MultiWAN QoS is a Quality of Service management tool for OpenWrt
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/multiwan-qos/conffiles
/etc/config/multiwan-qos
endef

define Package/multiwan-qos/install
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/etc/multiwan-qos.d
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_DIR) $(1)/lib/multiwan-qos
	$(INSTALL_DIR) $(1)/usr/lib/tc

	$(INSTALL_BIN) ./etc/multiwan-qos.sh $(1)/etc/
	$(INSTALL_BIN) ./etc/init.d/multiwan-qos $(1)/etc/init.d/
	$(INSTALL_DATA) ./lib/multiwan-qos/hotplug-common.sh $(1)/lib/multiwan-qos/
	$(INSTALL_CONF) ./etc/hotplug.d/iface/13-multiwan-qos-hotplug $(1)/etc/hotplug.d/iface/
	$(INSTALL_CONF) ./etc/config/multiwan-qos $(1)/etc/config/
	$(INSTALL_BIN) ./etc/uci-defaults/10-multiwan-qos-migrate-config $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./etc/config/multiwan-qos $(1)/etc/multiwan-qos.d/multiwan-qos-defaults
	$(INSTALL_DATA) ./usr/lib/tc/*.dist $(1)/usr/lib/tc/
	$(INSTALL_BIN) ./etc/multiwan-qos-agent-watchdog.lua $(1)/etc/
	$(INSTALL_BIN) ./www/cgi-bin/multiwan-qos-agent $(1)/www/cgi-bin/
	$(INSTALL_BIN) ./www/cgi-bin/qosmate-agent $(1)/www/cgi-bin/
endef

$(eval $(call BuildPackage,multiwan-qos))
