include $(TOPDIR)/rules.mk

PKG_NAME:=multiwan-qos
PKG_VERSION:=1.0.23
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
  DEPENDS:=+kmod-sched +ip-full +nftables +kmod-veth +tc-full +kmod-netem +kmod-sched-ctinfo +kmod-ifb +kmod-sched-cake +kmod-sched-red +kmod-sched-drr +kmod-sched-flower +lua +luci-lib-jsonc +jsonfilter +uclient-fetch +ethtool
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
	$(INSTALL_DATA) ./lib/multiwan-qos/process-lock.sh $(1)/lib/multiwan-qos/
	$(INSTALL_CONF) ./etc/hotplug.d/iface/13-multiwan-qos-hotplug $(1)/etc/hotplug.d/iface/
	$(INSTALL_CONF) ./etc/config/multiwan-qos $(1)/etc/config/
	$(INSTALL_BIN) ./etc/uci-defaults/10-multiwan-qos-migrate-config $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./etc/config/multiwan-qos $(1)/etc/multiwan-qos.d/multiwan-qos-defaults
	$(INSTALL_DATA) ./usr/lib/tc/*.dist $(1)/usr/lib/tc/
	$(INSTALL_BIN) ./www/cgi-bin/multiwan-qos-agent $(1)/www/cgi-bin/
	$(INSTALL_BIN) ./www/cgi-bin/qosmate-agent $(1)/www/cgi-bin/
	( cd $(1); \
		md5sum \
			etc/init.d/multiwan-qos \
			etc/multiwan-qos.sh \
			etc/multiwan-qos.d/multiwan-qos-defaults \
			lib/multiwan-qos/hotplug-common.sh \
			lib/multiwan-qos/process-lock.sh \
			usr/lib/tc/experimental.dist \
			usr/lib/tc/normal.dist \
			usr/lib/tc/normmix20-64.dist \
			usr/lib/tc/pareto.dist \
			usr/lib/tc/paretonormal.dist | \
		sed 's#  #  /#' > etc/multiwan-qos.d/backend_reg.md5 )
endef

define Package/multiwan-qos/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

if [ -x /etc/uci-defaults/10-multiwan-qos-migrate-config ]; then
	/bin/sh /etc/uci-defaults/10-multiwan-qos-migrate-config || true
	rm -f /etc/uci-defaults/10-multiwan-qos-migrate-config
fi

/etc/init.d/multiwan-qos check_deps >/dev/null 2>&1 || {
	echo "MultiWAN QoS: runtime dependency check failed; run '/etc/init.d/multiwan-qos install_deps' after package installation."
}
exit 0
endef

$(eval $(call BuildPackage,multiwan-qos))
