################################################################################
#
# toolchain-external
#
################################################################################

#
# This package implements the support for external toolchains, i.e
# toolchains that are available pre-built, ready to use. Such toolchain
# may either be readily available on the Web (Linaro, Sourcery
# CodeBench, from processor vendors) or may be built with tools like
# Crosstool-NG or Buildroot itself. So far, we have tested this
# with:
#
#  * Toolchains generated by Crosstool-NG
#  * Toolchains generated by Buildroot
#  * Toolchains provided by Linaro for the ARM and AArch64
#    architectures
#  * Sourcery CodeBench toolchains (from Mentor Graphics) for the ARM,
#    MIPS, PowerPC, x86, x86_64 and NIOS 2 architectures. For the MIPS
#    toolchain, the -muclibc variant isn't supported yet, only the
#    default glibc-based variant is.
#  * Analog Devices toolchains for the Blackfin architecture
#  * Xilinx toolchains for the Microblaze architecture
#  * Synopsys DesignWare toolchains for ARC cores
#
# The basic principle is the following
#
#  1. If the toolchain is not pre-installed, download and extract it
#  in $(TOOLCHAIN_EXTERNAL_INSTALL_DIR). Otherwise,
#  $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) points to were the toolchain has
#  already been installed by the user.
#
#  2. For all external toolchains, perform some checks on the
#  conformity between the toolchain configuration described in the
#  Buildroot menuconfig system, and the real configuration of the
#  external toolchain. This is for example important to make sure that
#  the Buildroot configuration system knows whether the toolchain
#  supports RPC, IPv6, locales, large files, etc. Unfortunately, these
#  things cannot be detected automatically, since the value of these
#  options (such as BR2_TOOLCHAIN_HAS_NATIVE_RPC) are needed at
#  configuration time because these options are used as dependencies
#  for other options. And at configuration time, we are not able to
#  retrieve the external toolchain configuration.
#
#  3. Copy the libraries needed at runtime to the target directory,
#  $(TARGET_DIR). Obviously, things such as the C library, the dynamic
#  loader and a few other utility libraries are needed if dynamic
#  applications are to be executed on the target system.
#
#  4. Copy the libraries and headers to the staging directory. This
#  will allow all further calls to gcc to be made using --sysroot
#  $(STAGING_DIR), which greatly simplifies the compilation of the
#  packages when using external toolchains. So in the end, only the
#  cross-compiler binaries remains external, all libraries and headers
#  are imported into the Buildroot tree.
#
#  5. Build a toolchain wrapper which executes the external toolchain
#  with a number of arguments (sysroot/march/mtune/..) hardcoded,
#  so we're sure the correct configuration is always used and the
#  toolchain behaves similar to an internal toolchain.
#  This toolchain wrapper and symlinks are installed into
#  $(HOST_DIR)/usr/bin like for the internal toolchains, and the rest
#  of Buildroot is handled identical for the 2 toolchain types.

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC)$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC),y)
LIB_EXTERNAL_LIBS += libatomic.so.* libc.so.* libcrypt.so.* libdl.so.* libgcc_s.so.* libm.so.* libnsl.so.* libresolv.so.* librt.so.* libutil.so.*
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC)$(BR2_ARM_EABIHF),yy)
LIB_EXTERNAL_LIBS += ld-linux-armhf.so.*
else
LIB_EXTERNAL_LIBS += ld*.so.*
endif
ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
LIB_EXTERNAL_LIBS += libpthread.so.*
ifneq ($(BR2_PACKAGE_GDB)$(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY),)
LIB_EXTERNAL_LIBS += libthread_db.so.*
endif # gdbserver
endif # ! no threads
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC),y)
LIB_EXTERNAL_LIBS += libnss_files.so.* libnss_dns.so.*
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL),y)
LIB_EXTERNAL_LIBS += libc.so libgcc_s.so.*
endif

ifeq ($(BR2_INSTALL_LIBSTDCPP),y)
USR_LIB_EXTERNAL_LIBS += libstdc++.so.*
endif

LIB_EXTERNAL_LIBS += $(call qstrip,$(BR2_TOOLCHAIN_EXTRA_EXTERNAL_LIBS))

# Details about sysroot directory selection.
#
# To find the sysroot directory, we use the trick of looking for the
# 'libc.a' file with the -print-file-name gcc option, and then
# mangling the path to find the base directory of the sysroot.
#
# Note that we do not use the -print-sysroot option, because it is
# only available since gcc 4.4.x, and we only recently dropped support
# for 4.2.x and 4.3.x.
#
# When doing this, we don't pass any option to gcc that could select a
# multilib variant (such as -march) as we want the "main" sysroot,
# which contains all variants of the C library in the case of multilib
# toolchains. We use the TARGET_CC_NO_SYSROOT variable, which is the
# path of the cross-compiler, without the --sysroot=$(STAGING_DIR),
# since what we want to find is the location of the original toolchain
# sysroot. This "main" sysroot directory is stored in SYSROOT_DIR.
#
# Then, multilib toolchains are a little bit more complicated, since
# they in fact have multiple sysroots, one for each variant supported
# by the toolchain. So we need to find the particular sysroot we're
# interested in.
#
# To do so, we ask the compiler where its sysroot is by passing all
# flags (including -march and al.), except the --sysroot flag since we
# want to the compiler to tell us where its original sysroot
# is. ARCH_SUBDIR will contain the subdirectory, in the main
# SYSROOT_DIR, that corresponds to the selected architecture
# variant. ARCH_SYSROOT_DIR will contain the full path to this
# location.
#
# One might wonder why we don't just bother with ARCH_SYSROOT_DIR. The
# fact is that in multilib toolchains, the header files are often only
# present in the main sysroot, and only the libraries are available in
# each variant-specific sysroot directory.


TOOLCHAIN_EXTERNAL_PREFIX = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PREFIX))
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD),y)
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(HOST_DIR)/opt/ext-toolchain
else
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PATH))
endif

ifeq ($(TOOLCHAIN_EXTERNAL_INSTALL_DIR),)
ifneq ($(TOOLCHAIN_EXTERNAL_PREFIX),)
# if no path set, figure it out from path
TOOLCHAIN_EXTERNAL_BIN := $(shell dirname $(shell which $(TOOLCHAIN_EXTERNAL_PREFIX)-gcc))
endif
else
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX),y)
TOOLCHAIN_EXTERNAL_BIN := $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/$(TOOLCHAIN_EXTERNAL_PREFIX)/bin
else
TOOLCHAIN_EXTERNAL_BIN := $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/bin
endif
endif

# If this is a buildroot toolchain, it already has a wrapper which we want to
# bypass. Since this is only evaluated after it has been extracted, we can use
# $(wildcard ...) here.
TOOLCHAIN_EXTERNAL_SUFFIX = \
	$(if $(wildcard $(TOOLCHAIN_EXTERNAL_BIN)/*.br_real),.br_real)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_SUFFIX='"$(TOOLCHAIN_EXTERNAL_SUFFIX)"'

TOOLCHAIN_EXTERNAL_CROSS = $(TOOLCHAIN_EXTERNAL_BIN)/$(TOOLCHAIN_EXTERNAL_PREFIX)-
TOOLCHAIN_EXTERNAL_CC = $(TOOLCHAIN_EXTERNAL_CROSS)gcc$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_CXX = $(TOOLCHAIN_EXTERNAL_CROSS)g++$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_READELF = $(TOOLCHAIN_EXTERNAL_CROSS)readelf$(TOOLCHAIN_EXTERNAL_SUFFIX)

ifeq ($(filter $(HOST_DIR)/%,$(TOOLCHAIN_EXTERNAL_BIN)),)
# TOOLCHAIN_EXTERNAL_BIN points outside HOST_DIR => absolute path
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_ABS='"$(TOOLCHAIN_EXTERNAL_BIN)"'
else
# TOOLCHAIN_EXTERNAL_BIN points inside HOST_DIR => relative path
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_REL='"$(TOOLCHAIN_EXTERNAL_BIN:$(HOST_DIR)/%=%)"'
endif

ifeq ($(call qstrip,$(BR2_GCC_TARGET_CPU_REVISION)),)
CC_TARGET_CPU_ := $(call qstrip,$(BR2_GCC_TARGET_CPU))
else
CC_TARGET_CPU_ := $(call qstrip,$(BR2_GCC_TARGET_CPU)-$(BR2_GCC_TARGET_CPU_REVISION))
endif
CC_TARGET_ARCH_ := $(call qstrip,$(BR2_GCC_TARGET_ARCH))
CC_TARGET_ABI_ := $(call qstrip,$(BR2_GCC_TARGET_ABI))
CC_TARGET_FPU_ := $(call qstrip,$(BR2_GCC_TARGET_FPU))
CC_TARGET_FLOAT_ABI_ := $(call qstrip,$(BR2_GCC_TARGET_FLOAT_ABI))
CC_TARGET_MODE_ := $(call qstrip,$(BR2_GCC_TARGET_MODE))

# march/mtune/floating point mode needs to be passed to the external toolchain
# to select the right multilib variant
ifeq ($(BR2_x86_64),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -m64
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_64
endif
ifneq ($(CC_TARGET_ARCH_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -march=$(CC_TARGET_ARCH_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARCH='"$(CC_TARGET_ARCH_)"'
endif
ifneq ($(CC_TARGET_CPU_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mcpu=$(CC_TARGET_CPU_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_CPU='"$(CC_TARGET_CPU_)"'
endif
ifneq ($(CC_TARGET_ABI_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mabi=$(CC_TARGET_ABI_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ABI='"$(CC_TARGET_ABI_)"'
endif
ifneq ($(CC_TARGET_FPU_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfpu=$(CC_TARGET_FPU_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_FPU='"$(CC_TARGET_FPU_)"'
endif
ifneq ($(CC_TARGET_FLOAT_ABI_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfloat-abi=$(CC_TARGET_FLOAT_ABI_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_FLOAT_ABI='"$(CC_TARGET_FLOAT_ABI_)"'
endif
ifneq ($(CC_TARGET_MODE_),)
TOOLCHAIN_EXTERNAL_CFLAGS += -m$(CC_TARGET_MODE_)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MODE='"$(CC_TARGET_MODE_)"'
endif
ifeq ($(BR2_BINFMT_FLAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -Wl,-elf2flt
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_BINFMT_FLAT
endif
ifeq ($(BR2_mipsel)$(BR2_mips64el),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MIPS_TARGET_LITTLE_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EL
endif
ifeq ($(BR2_mips)$(BR2_mips64),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MIPS_TARGET_BIG_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EB
endif
ifeq ($(BR2_arceb),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARC_TARGET_BIG_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EB
endif

TOOLCHAIN_EXTERNAL_CFLAGS += $(call qstrip,$(BR2_TARGET_OPTIMIZATION))

ifeq ($(BR2_SOFT_FLOAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -msoft-float
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_SOFTFLOAT=1
endif

# musl does not provide a sys/queue.h implementation, so add the
# netbsd-queue package that will install a sys/queue.h file in the
# staging directory based on the NetBSD implementation.
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
TOOLCHAIN_EXTERNAL_DEPENDENCIES += netbsd-queue
endif

# The Linaro ARMhf toolchain expects the libraries in
# {/usr,}/lib/arm-linux-gnueabihf, but Buildroot copies them to
# {/usr,}/lib, so we need to create a symbolic link.
define TOOLCHAIN_EXTERNAL_LINARO_ARMHF_SYMLINK
	ln -snf . $(TARGET_DIR)/lib/arm-linux-gnueabihf
	ln -snf . $(TARGET_DIR)/usr/lib/arm-linux-gnueabihf
endef

define TOOLCHAIN_EXTERNAL_LINARO_ARMEBHF_SYMLINK
	ln -snf . $(TARGET_DIR)/lib/armeb-linux-gnueabihf
	ln -snf . $(TARGET_DIR)/usr/lib/armeb-linux-gnueabihf
endef

define TOOLCHAIN_EXTERNAL_LINARO_AARCH64_SYMLINK
	ln -snf . $(TARGET_DIR)/lib/aarch64-linux-gnu
	ln -snf . $(TARGET_DIR)/usr/lib/aarch64-linux-gnu
endef

# Special handling for Blackfin toolchain, because of the split in two
# tarballs, and the organization of tarball contents. The tarballs
# contain ./opt/uClinux/{bfin-uclinux,bfin-linux-uclibc} directories,
# which themselves contain the toolchain. This is why we strip more
# components than usual.
define TOOLCHAIN_EXTERNAL_BLACKFIN_UCLIBC_EXTRA_EXTRACT
	$(call suitable-extractor,$(TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS)) $(DL_DIR)/$(TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS) | \
		$(TAR) --strip-components=3 --hard-dereference -C $(@D) $(TAR_OPTIONS) -
endef

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_ARM),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/arm-none-linux-gnueabi
TOOLCHAIN_EXTERNAL_SOURCE = arm-2014.05-29-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_ARAGO_ARMV7A_201109),y)
TOOLCHAIN_EXTERNAL_SITE = http://software-dl.ti.com/sdoemb/sdoemb_public_sw/arago_toolchain/2011_09/exports
TOOLCHAIN_EXTERNAL_SOURCE = arago-2011.09-armv7a-linux-gnueabi-sdk.tar.bz2
TOOLCHAIN_EXTERNAL_ACTUAL_SOURCE_TARBALL = arago-toolchain-2011.09-sources.tar.bz2
define TOOLCHAIN_EXTERNAL_FIXUP_CMDS
	mv $(@D)/arago-2011.09/armv7a/* $(@D)/
	rm -rf $(@D)/arago-2011.09/
endef
TOOLCHAIN_EXTERNAL_POST_EXTRACT_HOOKS += TOOLCHAIN_EXTERNAL_FIXUP_CMDS
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_ARAGO_ARMV5TE_201109),y)
TOOLCHAIN_EXTERNAL_SITE = http://software-dl.ti.com/sdoemb/sdoemb_public_sw/arago_toolchain/2011_09/exports
TOOLCHAIN_EXTERNAL_SOURCE = arago-2011.09-armv5te-linux-gnueabi-sdk.tar.bz2
TOOLCHAIN_EXTERNAL_ACTUAL_SOURCE_TARBALL = arago-toolchain-2011.09-sources.tar.bz2
define TOOLCHAIN_EXTERNAL_FIXUP_CMDS
	mv $(@D)/arago-2011.09/armv5te/* $(@D)/
	rm -rf $(@D)/arago-2011.09/
endef
TOOLCHAIN_EXTERNAL_POST_EXTRACT_HOOKS += TOOLCHAIN_EXTERNAL_FIXUP_CMDS
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_ARM),y)
ifeq ($(HOSTARCH),x86)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-arm-linux-gnueabihf-4.9-2014.09_linux.tar.xz
else
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/components/toolchain/binaries/5.1-2015.08/arm-linux-gnueabihf
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-5.1-2015.08-x86_64_arm-linux-gnueabihf.tar.xz
endif
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_ARMHF_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_ARMEB),y)
ifeq ($(HOSTARCH),x86)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-armeb-linux-gnueabihf-4.9-2014.09_linux.tar.xz
else
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/components/toolchain/binaries/5.1-2015.08/armeb-linux-gnueabihf
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-5.1-2015.08-x86_64_armeb-linux-gnueabihf.tar.xz
endif
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_ARMEBHF_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_MIPS),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/mips-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = mips-2015.11-32-mips-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_NIOSII),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/nios2-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = sourceryg++-2015.11-27-nios2-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_POWERPC),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/powerpc-mentor-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = mentor-2012.03-71-powerpc-mentor-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_SH),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/sh-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = renesas-2012.09-61-sh-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_X86),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/i686-pc-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = ia32-2012.09-62-i686-pc-linux-gnu-i386-linux.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_AMD64),y)
TOOLCHAIN_EXTERNAL_SITE = https://sourcery.mentor.com/public/gnu_toolchain/x86_64-amd-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = amd-2015.11-36-x86_64-amd-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_BLACKFIN_UCLINUX),y)
TOOLCHAIN_EXTERNAL_SITE = http://downloads.sourceforge.net/project/adi-toolchain/2014R1/2014R1-RC2/i386
TOOLCHAIN_EXTERNAL_SOURCE = blackfin-toolchain-2014R1-RC2.i386.tar.bz2
TOOLCHAIN_EXTERNAL_EXTRA_DOWNLOADS = blackfin-toolchain-uclibc-full-2014R1-RC2.i386.tar.bz2
TOOLCHAIN_EXTERNAL_STRIP_COMPONENTS = 3
TOOLCHAIN_EXTERNAL_POST_EXTRACT_HOOKS += TOOLCHAIN_EXTERNAL_BLACKFIN_UCLIBC_EXTRA_EXTRACT
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_LINARO_AARCH64),y)
ifeq ($(HOSTARCH),x86)
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/14.09/components/toolchain/binaries
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux.tar.xz
else
TOOLCHAIN_EXTERNAL_SITE = http://releases.linaro.org/components/toolchain/binaries/5.1-2015.08/aarch64-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = gcc-linaro-5.1-2015.08-x86_64_aarch64-linux-gnu.tar.xz
endif
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_LINARO_AARCH64_SYMLINK
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY_AARCH64),y)
TOOLCHAIN_EXTERNAL_SITE = http://sourcery.mentor.com/public/gnu_toolchain/aarch64-linux-gnu
TOOLCHAIN_EXTERNAL_SOURCE = aarch64-2014.05-30-aarch64-linux-gnu-i686-pc-linux-gnu.tar.bz2
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL_CROSS),y)
TOOLCHAIN_EXTERNAL_VERSION = 1.1.6
TOOLCHAIN_EXTERNAL_SITE = https://googledrive.com/host/0BwnS5DMB0YQ6bDhPZkpOYVFhbk0/musl-$(TOOLCHAIN_EXTERNAL_VERSION)
ifeq ($(BR2_arm),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-arm-linux-musleabi-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_armeb),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-armeb-linux-musleabi-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_i386),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-i486-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_microblazebe),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-microblaze-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_mips),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mips-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_mipsel),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-mipsel-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_powerpc),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-powerpc-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
else ifeq ($(BR2_x86_64),y)
TOOLCHAIN_EXTERNAL_SOURCE = crossx86-x86_64-linux-musl-$(TOOLCHAIN_EXTERNAL_VERSION).tar.xz
endif
else ifeq ($(BR2_TOOLCHAIN_EXTERNAL_SYNOPSYS_ARC_2014_12),y)
TOOLCHAIN_EXTERNAL_SITE = https://github.com/foss-for-synopsys-dwc-arc-processors/toolchain/releases/download/arc-2014.12
ifeq ($(BR2_arc750d)$(BR2_arc770d),y)
TOOLCHAIN_EXTERNAL_SYNOPSYS_CORE = arc700
else
TOOLCHAIN_EXTERNAL_SYNOPSYS_CORE = archs
endif
ifeq ($(BR2_arcle),y)
TOOLCHAIN_EXTERNAL_SYNOPSYS_ENDIANESS = le
else
TOOLCHAIN_EXTERNAL_SYNOPSYS_ENDIANESS = be
endif
TOOLCHAIN_EXTERNAL_SOURCE = arc_gnu_2014.12_prebuilt_uclibc_$(TOOLCHAIN_EXTERNAL_SYNOPSYS_ENDIANESS)_$(TOOLCHAIN_EXTERNAL_SYNOPSYS_CORE)_linux_install.tar.gz
else
# Custom toolchain
TOOLCHAIN_EXTERNAL_SITE = $(patsubst %/,%,$(dir $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_URL))))
TOOLCHAIN_EXTERNAL_SOURCE = $(notdir $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_URL)))
# We can't check hashes for custom downloaded toolchains
BR_NO_CHECK_HASH_FOR += $(TOOLCHAIN_EXTERNAL_SOURCE)
endif

# Some toolchain vendors have a regular file naming pattern.
# For them, mass-define _ACTUAL_SOURCE_TARBALL based _SITE.
ifneq ($(findstring sourcery.mentor.com/public/gnu_toolchain,$(TOOLCHAIN_EXTERNAL_SITE)),)
TOOLCHAIN_EXTERNAL_ACTUAL_SOURCE_TARBALL ?= \
	$(subst -i686-pc-linux-gnu.tar.bz2,.src.tar.bz2,$(subst -i686-pc-linux-gnu-i386-linux.tar.bz2,-i686-pc-linux-gnu.src.tar.bz2,$(TOOLCHAIN_EXTERNAL_SOURCE)))
else ifneq ($(findstring http://releases.linaro.org,$(TOOLCHAIN_EXTERNAL_SITE)),)
TOOLCHAIN_EXTERNAL_ACTUAL_SOURCE_TARBALL ?= \
	$(subst _linux.tar.xz,_src.tar.bz2,$(TOOLCHAIN_EXTERNAL_SOURCE))
endif

# In fact, we don't need to download the toolchain, since it is already
# available on the system, so force the site and source to be empty so
# that nothing will be downloaded/extracted.
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED),y)
TOOLCHAIN_EXTERNAL_SITE =
TOOLCHAIN_EXTERNAL_SOURCE =
endif

TOOLCHAIN_EXTERNAL_ADD_TOOLCHAIN_DEPENDENCY = NO

TOOLCHAIN_EXTERNAL_INSTALL_STAGING = YES

# Normal handling of downloaded toolchain tarball extraction.
ifneq ($(TOOLCHAIN_EXTERNAL_SOURCE),)
TOOLCHAIN_EXTERNAL_EXCLUDES = usr/lib/locale/*

# As a regular package, the toolchain gets extracted in $(@D), but
# since it's actually a fairly special package, we need it to be moved
# into TOOLCHAIN_EXTERNAL_INSTALL_DIR.
define TOOLCHAIN_EXTERNAL_MOVE
	rm -rf $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/*
	mkdir -p $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)
	mv $(@D)/* $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/
endef
TOOLCHAIN_EXTERNAL_POST_EXTRACT_HOOKS += \
	TOOLCHAIN_EXTERNAL_MOVE
endif

# Returns the location of the libc.a file for the given compiler + flags
define toolchain_find_libc_a
$$(readlink -f $$(LANG=C $(1) -print-file-name=libc.a))
endef

# Returns the sysroot location for the given compiler + flags. We need
# to handle cases where libc.a is in:
#
#  - lib/
#  - usr/lib/
#  - lib32/
#  - lib64/
#  - lib32-fp/ (Cavium toolchain)
#  - lib64-fp/ (Cavium toolchain)
#  - usr/lib/<tuple>/ (Linaro toolchain)
#
# And variations on these.
define toolchain_find_sysroot
$$(printf $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:(usr/)?lib(32|64)?([^/]*)?/([^/]*/)?libc\.a::')
endef

# Returns the lib subdirectory for the given compiler + flags (i.e
# typically lib32 or lib64 for some toolchains)
define toolchain_find_libdir
$$(printf $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:.*/(usr/)?(lib(32|64)?([^/]*)?)/([^/]*/)?libc.a:\2:')
endef

# Checks for an already installed toolchain: check the toolchain
# location, check that it supports sysroot, and then verify that it
# matches the configuration provided in Buildroot: ABI, C++ support,
# kernel headers version, type of C library and all C library features.
define TOOLCHAIN_EXTERNAL_CONFIGURE_CMDS
	$(Q)$(call check_cross_compiler_exists,$(TOOLCHAIN_EXTERNAL_CC))
	$(Q)$(call check_unusable_toolchain,$(TOOLCHAIN_EXTERNAL_CC))
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	$(call check_kernel_headers_version,\
		$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC)),\
		$(call qstrip,$(BR2_TOOLCHAIN_HEADERS_AT_LEAST))); \
	$(call check_gcc_version,$(TOOLCHAIN_EXTERNAL_CC),\
		$(call qstrip,$(BR2_TOOLCHAIN_GCC_AT_LEAST))); \
	if test "$(BR2_arm)" = "y" ; then \
		$(call check_arm_abi,\
			"$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS)",\
			$(TOOLCHAIN_EXTERNAL_READELF)) ; \
	fi ; \
	if test "$(BR2_INSTALL_LIBSTDCPP)" = "y" ; then \
		$(call check_cplusplus,$(TOOLCHAIN_EXTERNAL_CXX)) ; \
	fi ; \
	if test "$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC)" = "y" ; then \
		$(call check_uclibc,$${SYSROOT_DIR}) ; \
	elif test "$(BR2_TOOLCHAIN_EXTERNAL_MUSL)" = "y" ; then \
		$(call check_musl,$${SYSROOT_DIR}) ; \
	else \
		$(call check_glibc,$${SYSROOT_DIR}) ; \
	fi
endef

# With the musl C library, the libc.so library directly plays the role
# of the dynamic library loader. We just need to create a symbolic
# link to libc.so with the appropriate name.
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL),y)
ifeq ($(BR2_i386),y)
MUSL_ARCH = i386
else ifeq ($(BR2_ARM_EABIHF),y)
MUSL_ARCH = armhf
else
MUSL_ARCH = $(ARCH)
endif
define TOOLCHAIN_EXTERNAL_MUSL_LD_LINK
	ln -sf libc.so $(TARGET_DIR)/lib/ld-musl-$(MUSL_ARCH).so.1
endef
TOOLCHAIN_EXTERNAL_POST_INSTALL_STAGING_HOOKS += TOOLCHAIN_EXTERNAL_MUSL_LD_LINK
endif

# Integration of the toolchain into Buildroot: find the main sysroot
# and the variant-specific sysroot, then copy the needed libraries to
# the $(TARGET_DIR) and copy the whole sysroot (libraries and headers)
# to $(STAGING_DIR).
#
# Variables are defined as follows:
#
#  LIBC_A_LOCATION:     location of the libc.a file in the default
#                       multilib variant (allows to find the main
#                       sysroot directory)
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/usr/lib/libc.a
#
#  SYSROOT_DIR:         the main sysroot directory, deduced from
#                       LIBC_A_LOCATION by removing the
#                       usr/lib[32|64]/libc.a part of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/
#
# ARCH_LIBC_A_LOCATION: location of the libc.a file in the selected
#                       multilib variant (taking into account the
#                       CFLAGS). Allows to find the sysroot of the
#                       selected multilib variant.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/mips16/soft-float/el/usr/lib/libc.a
#
# ARCH_SYSROOT_DIR:     the sysroot of the selected multilib variant,
#                       deduced from ARCH_LIBC_A_LOCATION by removing
#                       usr/lib[32|64]/libc.a at the end of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/mips16/soft-float/el/
#
# ARCH_LIB_DIR:         'lib', 'lib32' or 'lib64' depending on where libraries
#                       are stored. Deduced from ARCH_LIBC_A_LOCATION by
#                       looking at usr/lib??/libc.a.
#                       Ex: lib
#
# ARCH_SUBDIR:          the relative location of the sysroot of the selected
#                       multilib variant compared to the main sysroot.
#			Ex: mips16/soft-float/el
#
# SUPPORT_LIB_DIR:      some toolchains, such as recent Linaro toolchains,
#                       store GCC support libraries (libstdc++,
#                       libgcc_s, etc.) outside of the sysroot. In
#                       this case, SUPPORT_LIB_DIR is set to a
#                       non-empty value, and points to the directory
#                       where these support libraries are
#                       available. Those libraries will be copied to
#                       our sysroot, and the directory will also be
#                       considered when searching libraries for copy
#                       to the target filesystem.

define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	SUPPORT_LIB_DIR="" ; \
	if test `find $${ARCH_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
		LIBSTDCPP_A_LOCATION=$$(LANG=C $(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
		if [ -e "$${LIBSTDCPP_A_LOCATION}" ]; then \
			SUPPORT_LIB_DIR=`readlink -f $${LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
		fi ; \
	fi ; \
	ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR}(.*)/$$:\1:"` ; \
	if test -z "$(BR2_STATIC_LIBS)" ; then \
		$(call MESSAGE,"Copying external toolchain libraries to target...") ; \
		for libs in $(LIB_EXTERNAL_LIBS); do \
			$(call copy_toolchain_lib_root,$${ARCH_SYSROOT_DIR},$${SUPPORT_LIB_DIR},$${ARCH_LIB_DIR},$$libs,/lib); \
		done ; \
		for libs in $(USR_LIB_EXTERNAL_LIBS); do \
			$(call copy_toolchain_lib_root,$${ARCH_SYSROOT_DIR},$${SUPPORT_LIB_DIR},$${ARCH_LIB_DIR},$$libs,/usr/lib); \
		done ; \
	fi ; \
	if test "$(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY)" = "y"; then \
		$(call MESSAGE,"Copying gdbserver") ; \
		gdbserver_found=0 ; \
		for d in $${ARCH_SYSROOT_DIR}/usr \
			 $${ARCH_SYSROOT_DIR}/../debug-root/usr \
			 $${ARCH_SYSROOT_DIR}/usr/$${ARCH_LIB_DIR} \
			 $(TOOLCHAIN_EXTERNAL_INSTALL_DIR); do \
			if test -f $${d}/bin/gdbserver ; then \
				install -m 0755 -D $${d}/bin/gdbserver $(TARGET_DIR)/usr/bin/gdbserver ; \
				gdbserver_found=1 ; \
				break ; \
			fi ; \
		done ; \
		if [ $${gdbserver_found} -eq 0 ] ; then \
			echo "Could not find gdbserver in external toolchain" ; \
			exit 1 ; \
		fi ; \
	fi
endef

define TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	if test -z "$${SYSROOT_DIR}" ; then \
		@echo "External toolchain doesn't support --sysroot. Cannot use." ; \
		exit 1 ; \
	fi ; \
	ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	SUPPORT_LIB_DIR="" ; \
	if test `find $${ARCH_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
		LIBSTDCPP_A_LOCATION=$$(LANG=C $(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
		if [ -e "$${LIBSTDCPP_A_LOCATION}" ]; then \
			SUPPORT_LIB_DIR=`readlink -f $${LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
		fi ; \
	fi ; \
	ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR}(.*)/$$:\1:"` ; \
	$(call MESSAGE,"Copying external toolchain sysroot to staging...") ; \
	$(call copy_toolchain_sysroot,$${SYSROOT_DIR},$${ARCH_SYSROOT_DIR},$${ARCH_SUBDIR},$${ARCH_LIB_DIR},$${SUPPORT_LIB_DIR})
endef

# Special installation target used on the Blackfin architecture when
# FDPIC is not the primary binary format being used, but the user has
# nonetheless requested the installation of the FDPIC libraries to the
# target filesystem.
ifeq ($(BR2_BFIN_INSTALL_FDPIC_SHARED),y)
define TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FDPIC
	$(Q)$(call MESSAGE,"Install external toolchain FDPIC libraries to target...") ; \
	FDPIC_EXTERNAL_CC=$(dir $(TOOLCHAIN_EXTERNAL_CC))/../../bfin-linux-uclibc/bin/bfin-linux-uclibc-gcc ; \
	FDPIC_SYSROOT_DIR="$(call toolchain_find_sysroot,$${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	FDPIC_LIB_DIR="$(call toolchain_find_libdir,$${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	FDPIC_SUPPORT_LIB_DIR="" ; \
	if test `find $${FDPIC_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
	        FDPIC_LIBSTDCPP_A_LOCATION=$$(LANG=C $${FDPIC_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
	        if [ -e "$${FDPIC_LIBSTDCPP_A_LOCATION}" ]; then \
	                FDPIC_SUPPORT_LIB_DIR=`readlink -f $${FDPIC_LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
	        fi ; \
	fi ; \
	for libs in $(LIB_EXTERNAL_LIBS); do \
	        $(call copy_toolchain_lib_root,$${FDPIC_SYSROOT_DIR},$${FDPIC_SUPPORT_LIB_DIR},$${FDPIC_LIB_DIR},$$libs,/lib); \
	done ; \
	for libs in $(USR_LIB_EXTERNAL_LIBS); do \
	        $(call copy_toolchain_lib_root,$${FDPIC_SYSROOT_DIR},$${FDPIC_SUPPORT_LIB_DIR},$${FDPIC_LIB_DIR},$$libs,/usr/lib); \
	done
endef
endif

# Special installation target used on the Blackfin architecture when
# shared FLAT is not the primary format being used, but the user has
# nonetheless requested the installation of the shared FLAT libraries
# to the target filesystem. The flat libraries are found and linked
# according to the index in name "libN.so". Index 1 is reserved for
# the standard C library. Customer libraries can use 4 and above.
ifeq ($(BR2_BFIN_INSTALL_FLAT_SHARED),y)
define TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FLAT
	$(Q)$(call MESSAGE,"Install external toolchain FLAT libraries to target...") ; \
	FLAT_EXTERNAL_CC=$(dir $(TOOLCHAIN_EXTERNAL_CC))../../bfin-uclinux/bin/bfin-uclinux-gcc ; \
	FLAT_LIBC_A_LOCATION=`$${FLAT_EXTERNAL_CC} $(TOOLCHAIN_EXTERNAL_CFLAGS) -mid-shared-library -print-file-name=libc`; \
	if [ -f $${FLAT_LIBC_A_LOCATION} -a ! -h $${FLAT_LIBC_A_LOCATION} ] ; then \
	        $(INSTALL) -D $${FLAT_LIBC_A_LOCATION} $(TARGET_DIR)/lib/lib1.so; \
	fi
endef
endif

# Build toolchain wrapper for preprocessor, C and C++ compiler and setup
# symlinks for everything else. Skip gdb symlink when we are building our
# own gdb to prevent two gdb's in output/host/usr/bin.
# The LTO support in gcc creates wrappers for ar, ranlib and nm which load
# the lto plugin. These wrappers are called *-gcc-ar, *-gcc-ranlib, and
# *-gcc-nm and should be used instead of the real programs when -flto is
# used. However, we should not add the toolchain wrapper for them, and they
# match the *cc-* pattern. Therefore, an additional case is added for *-ar,
# *-ranlib and *-nm.
define TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER
	$(Q)cd $(HOST_DIR)/usr/bin; \
	for i in $(TOOLCHAIN_EXTERNAL_CROSS)*; do \
		base=$${i##*/}; \
		case "$$base" in \
		*-ar|*-ranlib|*-nm) \
			ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%../..%') .; \
			;; \
		*cc|*cc-*|*++|*++-*|*cpp) \
			ln -sf toolchain-wrapper $$base; \
			;; \
		*gdb|*gdbtui) \
			if test "$(BR2_PACKAGE_HOST_GDB)" != "y"; then \
				ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%../..%') .; \
			fi \
			;; \
		*) \
			ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%../..%') .; \
			;; \
		esac; \
	done
endef

#
# Generate gdbinit file for use with Buildroot
#
define TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT
	$(Q)if test -f $(TARGET_CROSS)gdb ; then \
		$(call MESSAGE,"Installing gdbinit"); \
		$(gen_gdbinit_file); \
	fi
endef

# uClibc-ng dynamic loader is called ld-uClibc.so.1, but gcc is not
# patched specifically for uClibc-ng, so it continues to generate
# binaries that expect the dynamic loader to be named ld-uClibc.so.0,
# like with the original uClibc. Therefore, we create an additional
# symbolic link to make uClibc-ng systems work properly.
define TOOLCHAIN_EXTERNAL_FIXUP_UCLIBCNG_LDSO
	$(Q)if test -e $(TARGET_DIR)/lib/ld-uClibc.so.1; then \
		ln -sf ld-uClibc.so.1 $(TARGET_DIR)/lib/ld-uClibc.so.0 ; \
	fi
	$(Q)if test -e $(TARGET_DIR)/lib/ld64-uClibc.so.1; then \
		ln -sf ld64-uClibc.so.1 $(TARGET_DIR)/lib/ld64-uClibc.so.0 ; \
	fi
endef

TOOLCHAIN_EXTERNAL_BUILD_CMDS = $(TOOLCHAIN_BUILD_WRAPPER)

define TOOLCHAIN_EXTERNAL_INSTALL_STAGING_CMDS
	$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)
	$(TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER)
	$(TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT)
endef

# Even though we're installing things in both the staging, the host
# and the target directory, we do everything within the
# install-staging step, arbitrarily.
define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_CMDS
	$(TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS)
	$(TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FDPIC)
	$(TOOLCHAIN_EXTERNAL_INSTALL_BFIN_FLAT)
	$(TOOLCHAIN_EXTERNAL_FIXUP_UCLIBCNG_LDSO)
endef

$(eval $(generic-package))
