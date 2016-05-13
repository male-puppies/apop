#
# Copyright (C) 2006-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ac9531_reset_button
PKG_VERSION:=2016-05-12
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=
PKG_MAINTAINER:=flead <164035526@qq.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/ac9531_reset_button
	SECTION:=Applications
	CATEGORY:=Puppies
	TITLE:=self init script
endef

define Package/ac9531_reset_button/description
	AC_QCA9531_RESET_BUTTON
endef


define Build/Prepare
	true
endef

define Build/Compile
	true
endef

define Package/ac9531_reset_button/install	
	$(CP) -a ./root/* $(1)/
endef

define Package/ac9531_reset_button/postinst
	true
	exit 0
endef

define Package/ac9531_reset_button/prerm
	true
	exit 0
endef

$(eval $(call BuildPackage,ac9531_reset_button))
