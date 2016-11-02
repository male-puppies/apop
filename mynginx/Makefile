include $(TOPDIR)/rules.mk

PKG_NAME:=mynginx
PKG_VERSION:=0.1
PKG_RELEASE:=0

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=Ivan <itgb1989@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
SRC_DIR:= nginx-1.4.7

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=mynginx
	DEPENDS:=+nginx
endef

define Package/$(PKG_NAME)/description
	mynginx
endef

define Build/Compile
	echo "--------------------"
endef

define Package/$(PKG_NAME)/install
	$(CP) -a ./root/* $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
