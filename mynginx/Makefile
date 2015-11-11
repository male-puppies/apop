include $(TOPDIR)/rules.mk

PKG_NAME:=mynginx
PKG_VERSION:=0.1
PKG_RELEASE:=0

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=Ivan <itgb1989@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR:= se

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=apps
	TITLE:=mynginx
	#DEPENDS:=+lua53
endef

define Package/$(PKG_NAME)/description
	se library
endef

define Build/Compile
	echo "--------------------" $(BUILD_DIR)/lua53/src
	#$(MAKE) -C $(SRC_DIR) LUA_SO_DIR=$(BUILD_DIR)/lua53/src $(TARGET_CONFIGURE_OPTS)  
	
	#$(MAKE)  -C $(SRC_DIR)/se \
	#	CC="$(TARGET_CROSS)gcc" \
	#	AR="$(TARGET_CROSS)ar rcu" \
	#	RANLIB="$(TARGET_CROSS)ranlib" \
	#	INSTALL_ROOT=/usr \
	#	CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS) -fPIC" \
	#	MYLDFLAGS="$(TARGET_LDFLAGS)" \
	#	PKG_VERSION=$(PKG_VERSION)
endef

define Package/$(PKG_NAME)/install  
	#$(INSTALL_DIR) $(1)/usr/lib/lua 
	#$(CP) $(SRC_DIR)/bin/se.so $(1)/usr/lib/lua 
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
