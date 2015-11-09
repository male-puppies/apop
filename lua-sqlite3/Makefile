include $(TOPDIR)/rules.mk

PKG_NAME:=lua-sqlite3
PKG_VERSION:=0.1
PKG_RELEASE:=0

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=helloshiki <aquariusye@163.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=lua-sqlite3
	DEPENDS:=+liblua sqlite3.9
endef

define Package/$(PKG_NAME)/description
	Lua bindings to sqlite3
endef

define Build/Compile
	$(MAKE) -C lua-sqlite3 LUA53_SO_DIR=$(BUILD_DIR)/lua53/src  LUA_INC=$(BUILD_DIR)/lua-5.1.5/src $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/lib/lua/
	cd lua-sqlite3 && $(INSTALL_BIN) *.so $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
