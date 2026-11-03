include $(TOPDIR)/rules.mk

PKG_NAME:=multiwan-nft-nping
PKG_VERSION:=7.992
PKG_RELEASE:=1
PKG_SOURCE:=nmap-$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://nmap.org/dist/
PKG_HASH:=0c12660eddbf7eabeff6996cb0c044a4eadf2bb0c6fbcb340d6cf72b1caee402
PKG_BUILD_DIR:=$(BUILD_DIR)/nmap-$(PKG_VERSION)
PKG_LICENSE:=NPSL-0.95
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/multiwan-nft-nping
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Nping with working IPv6 probing
  URL:=https://nmap.org/nping/
  DEPENDS:=+libstdcpp +libpthread
  PROVIDES:=nping
  CONFLICTS:=nping nping-ssl
  REPLACES:=nping nping-ssl
endef

define Package/multiwan-nft-nping/description
Optional Nping replacement for MultiWAN tracking. Uses the upstream OpenWrt
source version with IPv6 source selection and capture-filter fixes. Only the
probe executable is built; the rest of the Nmap suite is not included.
endef

CONFIGURE_ARGS += \
	--with-nping \
	--with-libpcap=included \
	--with-libdnet=included \
	--without-ncat \
	--without-ndiff \
	--without-zenmap \
	--without-liblua \
	--without-libssh2 \
	--without-openssl \
	--without-localdirs

CONFIGURE_VARS += ac_cv_dnet_bsd_bpf=no

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS) build-pcap build-dnet build-nbase
	+$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS) build-netutil build-nsock
	+$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR) $(TARGET_CONFIGURE_OPTS) build-nping
endef

define Package/multiwan-nft-nping/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/nping/nping $(1)/usr/bin/
endef

$(eval $(call BuildPackage,multiwan-nft-nping))
