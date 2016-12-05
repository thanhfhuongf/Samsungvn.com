#!/bin/bash
while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        --skip)
            SKIP=1
            ;;
        --variant)
            VARIANT=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

CLEAN_RAMDISK()
{
	[ -d $DARKLORD_OUTPUT/ramdisk ] && {
		echo "Removing old ramdisk..."
		rm -rf $DARKLORD_OUTPUT/ramdisk
	}
}

SET_PERMISSIONS()
{
	echo "Setting ramdisk file permissions..."
	cd $DARKLORD_OUTPUT/ramdisk
	# set all directories to 0755 by default
	find -type d -exec chmod 0755 {} \;
	# set all files to 0644 by default
	find -type f -exec chmod 0644 {} \;
	# scripts should be 0750
	find -name "*.rc" -exec chmod 0750 {} \;
	find -name "*.sh" -exec chmod 0750 {} \;
	# init and everything in /sbin should be 0750
	chmod -Rf 0750 init sbin
	chmod 0771 carrier data
}

SETUP_RAMDISK()
{
	echo "Building ramdisk structure..."
	cd $DARKLORD_PATH
	mkdir -p $DARKLORD_OUTPUT/ramdisk
	rsync -a $DARKLORD_PATH/dist/variant/$VARIANT/ramdisk/ $DARKLORD_OUTPUT/ramdisk
	cd $DARKLORD_OUTPUT/ramdisk
	mkdir -p dev proc sys system kmod carrier data
}


BUILD_KERNEL()
{
	if [ "$SKIP" != "1" ] ; then
		make clean -C $KERNEL_SOURCE
	fi	

	make -C $KERNEL_SOURCE -j8 CONFIG_NO_ERROR_ON_MISMATCH=y CONFIG_DEBUG_SECTION_MISMATCH=y $VARIANT_DEFCONFIG
	make -C $KERNEL_SOURCE -j8 CONFIG_NO_ERROR_ON_MISMATCH=y CONFIG_DEBUG_SECTION_MISMATCH=y

	CLEAN_RAMDISK
	SETUP_RAMDISK
	SET_PERMISSIONS

	cd $DARKLORD_OUTPUT/ramdisk
	echo "Building ramdisk.img..."
	find | fakeroot cpio -o -H newc | gzip -9 > $DARKLORD_OUTPUT/arch/arm64/boot/ramdisk.cpio.gz
	cd $DARKLORD_OUTPUT

	$DARKLORD_PATH/mkbootimg_tools/mkbootimg --kernel $DARKLORD_OUTPUT/arch/arm64/boot/Image \
	--ramdisk $DARKLORD_OUTPUT/arch/arm64/boot/ramdisk.cpio.gz \
	--dt $DARKLORD_PATH/dist/variant/$VARIANT/dt.img \
	--base 0x10000000 \
	--pagesize 2048 \
	--ramdisk_offset 0x01000000 \
	--tags_offset 0x00000100 \
	--second_offset 0x00f00000 \
	--output $DARKLORD_PATH/kernelzip/boot.img


	echo -n "SEANDROIDENFORCE" >> $DARKLORD_PATH/kernelzip/boot.img

	GENERATED_SIZE=$(stat -c %s $DARKLORD_PATH/kernelzip/boot.img)
	if echo "$@" | grep -q "CC=\$(CROSS_COMPILE)gcc" ; then
		dd if=/dev/zero bs=$((${PARTITION_SIZE}-${GENERATED_SIZE})) count=1 >> $DARKLORD_PATH/kernelzip/boot.img
	fi

	KERNEL_ZIP=$KERNEL_RELEASE_PATH/$DARKLORD_FULLVER.zip

	rm -Rf $KERNEL_ZIP.zip
	cd $DARKLORD_PATH/kernelzip/
	7za a $KERNEL_ZIP *
	cd $DARKLORD_PATH
	ls -al $KERNEL_ZIP

	CLEAN_RAMDISK
	cd $DARKLORD_PATH
}

BUILD_VARIANT()
{
	export VARIANT_DEFCONFIG="exynos7420-noblelte_"$VARIANT"_defconfig"
	if ! [ -f $DARKLORD_PATH"/../arch/arm64/configs/"$VARIANT_DEFCONFIG ] ; then
		echo "Device "$VARIANT_DEFCONFIG" not found in arm configs!"
	else
		export KERNEL_VARIANT=${VARIANT/_/-}
		export DARKLORD_FULLVER=$KERNEL_NAME-$KERNEL_VARIANT-$KERNEL_VERSION
		BUILD_KERNEL
	fi
}

export ARCH=arm64
export LD_LIBRARY_PATH=/home/thanhfhuongf/kernel/Toolchain/aarch64-sabermod-7.0/lib
export CROSS_COMPILE=/home/thanhfhuongf/kernel/Toolchain/aarch64-sabermod-7.0/bin/aarch64-
export DARKLORD_PATH=$(pwd)
export DARKLORD_OUTPUT="$DARKLORD_PATH/../"
export KERNEL_SOURCE="$DARKLORD_PATH/../"
export KERNEL_VERSION=$(cat kernel_version)
export KERNEL_NAME="Stock.GraceUX"
export KERNEL_RELEASE_PATH="$DARKLORD_PATH/release/$KERNEL_NAME/$KERNEL_VERSION"
export KBUILD_BUILD_USER="thanhfhuongf"
export KBUILD_BUILD_HOST="samsungvn.com"
export PARTITION_SIZE=29360128


if ! [ -d "$KERNEL_RELEASE_PATH" ] ; then
	mkdir -p $KERNEL_RELEASE_PATH
fi

if [ "$VARIANT" != "" ] ; then
	BUILD_VARIANT
else
	for V in dist/variant/*
	do
		VARIANT=${V#dist/variant/}
		BUILD_VARIANT
	done;
fi;
