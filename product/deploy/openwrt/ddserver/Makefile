include $(TOPDIR)/rules.mk

PKG_NAME:=ddserver
PKG_VERSION:=0.2
PKG_RELEASE:=15

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/ddserver
  SECTION:=multimedia
  CATEGORY:=Multimedia
  TITLE:=DslrDashboard Server
  DEPENDS:=+libusb-1.0 +libpthread +libstdcpp
endef

define Package/ddserver/description
  DslrDashboardServer provides a USB/PTP bridge for DSLR remote control clients.
endef

define Package/ddserver/conffiles
/etc/d810-ddserver.env
endef

CMAKE_OPTIONS += -DDDSERVER_INSTALL_SYSTEMD=OFF
CMAKE_OPTIONS += -DCMAKE_BUILD_TYPE=Release
CMAKE_OPTIONS += -DCMAKE_CXX_STANDARD=11

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/CMakeLists.txt $(PKG_BUILD_DIR)/
	$(CP) $(CURDIR)/src $(PKG_BUILD_DIR)/
	$(CP) $(CURDIR)/files $(PKG_BUILD_DIR)/
endef

define Package/ddserver/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ddserver $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_CONF) $(CURDIR)/files/d810-ddserver.env $(1)/etc/d810-ddserver.env
endef

$(eval $(call BuildPackage,ddserver))
