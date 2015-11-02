include $(TOPDIR)/rules.mk

PKG_NAME:=sqlite3.9
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR=sqlite-autoconf-3090100
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=sqlite3.9
endef

define Package/$(PKG_NAME)/description
	sqlite3.9
endef

define Build/Compile
	#cd $(SRC_DIR) && ./configure
	$(MAKE) -C $(SRC_DIR) $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	#$(INSTALL_DIR) $(1)/usr/sbin
	#$(INSTALL_DIR) $(1)/usr/lib
	#$(INSTALL_BIN) $(SRC_DIR)/src/mosquitto $(1)/usr/sbin
	#$(INSTALL_BIN) $(SRC_DIR)/client/mosquitto_* $(1)/usr/sbin
	#$(INSTALL_BIN) $(SRC_DIR)/lib/libmosquitto.so* $(1)/usr/lib
	#$(CP) -a ./root/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
