include $(TOPDIR)/rules.mk

PKG_NAME:=lua-se
PKG_VERSION:=2015-08-20
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=helloshiki <aquariusye@163.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=lua-se
	DEPENDS:=+liblua
endef

define Package/$(PKG_NAME)/description
	Lua bindings to se
endef

define Build/Compile
	$(MAKE) -C se LUA_INC=$(BUILD_DIR)/lua-5.1.5/src $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/lib/lua/
	$(INSTALL_BIN) se/bin/se.so $(1)/usr/lib/lua/
	#$(INSTALL_DATA) se/bin/*.lua $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
