include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-multiwan-qos
PKG_VERSION:=1.0.49
PKG_RELEASE:=1
PKG_PO_VERSION:=1.0.49-r1

PKG_MAINTAINER:=Markus Hütter <mh@hudra.net>
PKG_LICENSE:=GPL-3.0-or-later

LUCI_TITLE:=LuCI support for MultiWAN QoS
LUCI_DEPENDS:=+multiwan-qos +luci-lib-jsonc +lua +jq
LUCI_PKGARCH:=all
PKG_PROVIDES:=luci-app-qosmate
PKG_CONFLICTS:=luci-app-qosmate
PKG_REPLACES:=luci-app-qosmate

PO_LANG:=de

include $(TOPDIR)/feeds/luci/luci.mk

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/multiwan-qos
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_DIR) $(1)/etc/multiwan-qos.d

	$(INSTALL_DATA) ./htdocs/luci-static/resources/multiwan-qos/*.js $(1)/www/luci-static/resources/view/multiwan-qos/

	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-multiwan-qos.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-multiwan-qos.json $(1)/usr/share/rpcd/acl.d/

	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.multiwan_qos $(1)/usr/libexec/rpcd/
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.multiwan_qos_stats $(1)/usr/libexec/rpcd/
	( cd $(1); \
		md5sum \
			usr/share/luci/menu.d/luci-app-multiwan-qos.json \
			usr/share/rpcd/acl.d/luci-app-multiwan-qos.json \
			usr/libexec/rpcd/luci.multiwan_qos \
			usr/libexec/rpcd/luci.multiwan_qos_stats \
			www/luci-static/resources/view/multiwan-qos/settings.js \
			www/luci-static/resources/view/multiwan-qos/hfsc.js \
			www/luci-static/resources/view/multiwan-qos/cake.js \
			www/luci-static/resources/view/multiwan-qos/advanced.js \
			www/luci-static/resources/view/multiwan-qos/rules.js \
			www/luci-static/resources/view/multiwan-qos/ratelimits.js \
			www/luci-static/resources/view/multiwan-qos/connections.js \
			www/luci-static/resources/view/multiwan-qos/custom_rules.js \
			www/luci-static/resources/view/multiwan-qos/ipsets.js \
			www/luci-static/resources/view/multiwan-qos/statistics.js \
			www/luci-static/resources/view/multiwan-qos/agent.js | \
		sed 's#  #  /#' > etc/multiwan-qos.d/frontend_reg.md5 )
endef

# call BuildPackage - OpenWrt buildroot signature

$(eval $(call BuildPackage,$(PKG_NAME)))
