include $(TOPDIR)/rules.mk

PKG_NAME:=mynginx
PKG_VERSION:=0.1
PKG_RELEASE:=0

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=Ivan <itgb1989@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR:= nginx-1.9.6

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=mynginx
	DEPENDS:=+liblua +libpcre +libopenssl +libpthread
endef

define Package/$(PKG_NAME)/description
	mynginx
endef

define Build/Compile
	echo "--------------------" $(BUILD_DIR)/lua53/src
	#cd $(SRC_DIR) && ./cfg.sh $(BUILD_DIR)/lua-5.1.5/src 
	$(MAKE) -C $(SRC_DIR) $(TARGET_CONFIGURE_OPTS)
endef

define Package/$(PKG_NAME)/install  
	$(INSTALL_DIR) $(1)/usr/sbin
	cp $(SRC_DIR)/objs/nginx $(1)/usr/sbin
	$(CP) -a ./root/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
