include $(TOPDIR)/rules.mk

PKG_NAME:=myiconv
PKG_VERSION:=0.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR=libiconv-1.14
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=myiconv
endef

define Package/$(PKG_NAME)/description
	myiconv
endef

define Build/Compile 
	#cd $(SRC_DIR) && ./configure --host=mipsel-openwrt-linux
	$(MAKE) -C $(SRC_DIR) $(TARGET_CONFIGURE_OPTS)
	$(STRIP) $(SRC_DIR)/lib/.libs/libiconv.so.2.5.1
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(SRC_DIR)/src/.libs/iconv_no_i18n  $(1)/usr/bin/iconv
	$(INSTALL_BIN) $(SRC_DIR)/lib/.libs/libiconv.so.2 $(1)/usr/lib
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
