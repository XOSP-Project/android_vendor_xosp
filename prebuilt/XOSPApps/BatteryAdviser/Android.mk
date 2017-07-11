#
# Copyright (C) 2017 The Xperia Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
LOCAL_PATH := $(call my-dir)/../../../../../essentials_xosp_apps

include $(CLEAR_VARS)

LOCAL_MODULE := BatteryAdviser
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_BUILT_MODULE_STEM := package.apk
LOCAL_CERTIFICATE := $(DEFAULT_SYSTEM_DEV_CERTIFICATE)
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := essentials/BatteryAdviser/BatteryAdviser.apk
LOCAL_MODULE_PATH   := $(PRODUCT_OUT)/system/app
include $(BUILD_PREBUILT)

ifeq ($(TARGET_ARCH), arm64)
$(shell mkdir -p $(PRODUCT_OUT)/system/app/BatteryAdviser/lib/arm64 && cp essentials_xosp_apps/essentials/BatteryAdviser/lib/arm64/libpbp.so $(PRODUCT_OUT)/system/app/BatteryAdviser/lib/arm64)
else
$(shell mkdir -p $(PRODUCT_OUT)/system/app/BatteryAdviser/lib/arm && cp essentials_xosp_apps/essentials/BatteryAdviser/lib/arm/libpbp.so $(PRODUCT_OUT)/system/app/BatteryAdviser/lib/arm)
endif