echo ""
echo "# Supported devices"
echo "blazer     = Pixel 10 Pro"
echo "mustang    = Pixel 10 Pro XL"
echo "rango      = Pixel 10 Pro Fold"
echo "frankel    = Pixel 10"
echo "stallion   = Pixel 10a"
DEVICES="blazer mustang rango frankel stallion"

echo "# Supported releases of Android"
echo "Android 16"
echo ""
RELEASES="16"

DEVICE="$(getprop ro.product.device)"
DEVICE_FOUND=0
for dev in $DEVICES; do
  if [ "$dev" = "$DEVICE" ]; then
    DEVICE_FOUND=1
    break
  fi
done
if [ "$DEVICE_FOUND" -eq 0 ]; then
  abort "* Device $DEVICE is not supported!"
fi

RELEASE="$(getprop ro.build.version.release)"
RELEASE_FOUND=0
for rel in $RELEASES; do
  if [ "$rel" = "$RELEASE" ]; then
    RELEASE_FOUND=1
    break
  fi
done
if [ "$RELEASE_FOUND" -eq 0 ]; then
  abort "* Android $RELEASE is not supported!"
fi

PATH="$MODDIR/bin:$PATH"
SLOT="$(getprop | grep ro.boot.slot_suffix | sed -e 's/.*: \[\(.*\)\].*/\1/')"
BOOT=boot
if [ -b "/dev/block/bootdevice/by-name/init_boot$SLOT" ]; then
  BOOT=init_boot
fi

cd "$MODDIR"
chmod +x "$MODDIR/bin/magiskboot"
chmod +x "$MODDIR/bin/zramcfg"
chmod +x "$MODDIR/service.sh"

echo "* Copying $BOOT$SLOT"
cp /dev/block/bootdevice/by-name/$BOOT$SLOT $BOOT.img

echo "* Unpacking $BOOT$SLOT"
rm $BOOT-new.img header kernel ramdisk.cpio >/dev/null 2>&1
magiskboot unpack -h $BOOT.img >/dev/null 2>&1

echo "* Adjusting ramdisk"
cd ramdisk
IFS=$'\n'; set -f
for d in $(find . -type d)
do
  if [ $d == "." ]; then
    continue
  fi
  DIR="${d#./}"
  echo "- $DIR"
  magiskboot cpio ../ramdisk.cpio "mkdir 0777 $DIR" >/dev/null 2>&1
done
for f in $(find . -type f)
do
  FILE="${f#./}"
  echo "- $FILE"
  magiskboot cpio ../ramdisk.cpio "rm $FILE" >/dev/null 2>&1
  magiskboot cpio ../ramdisk.cpio "add 0777 $FILE $FILE" >/dev/null 2>&1
done
unset IFS; set +f
cd ..

echo "* Repacking $BOOT$SLOT"
magiskboot repack $BOOT.img $BOOT-new.img
rm header kernel ramdisk.cpio

echo "* Flashing $BOOT$SLOT"
cp $BOOT-new.img /dev/block/bootdevice/by-name/$BOOT$SLOT

echo "* Cleaning up"
rm $BOOT.img $BOOT-new.img header kernel ramdisk.cpio
rm -rf META-INF

echo "* Syncing"
sync
