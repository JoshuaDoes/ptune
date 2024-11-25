echo ""
echo "# Supported devices"
echo "raven     = Pixel 6 Pro"
echo "oriole    = Pixel 6"
echo "bluejay   = Pixel 6a"
echo "cheetah   = Pixel 7 Pro"
echo "panther   = Pixel 7"
echo "lynx      = Pixel 7a"
echo "felix     = Pixel Fold"
echo "tangorpro = Pixel Tablet"
echo "husky     = Pixel 8 Pro"
echo "shiba     = Pixel 8"
echo "akita     = Pixel 8a"
echo "caiman    = Pixel 9 Pro"
echo "komodo    = Pixel 9 Pro XL"
echo "comet     = Pixel 9 Pro Fold"
echo "tokay     = Pixel 9"
echo ""
DEVICES="raven oriole bluejay cheetah panther lynx felix tangorpro husky shiba akita caiman komodo comet tokay"

echo "# Supported releases"
echo "Android 14"
echo "Android 15"
echo ""
RELEASES="14 15"

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
BOOT=boot.img

cd "$MODDIR"
chmod +x "$MODDIR/bin/magiskboot"
chmod +x "$MODDIR/service.sh"

echo "* Copying boot$SLOT"
cp /dev/block/bootdevice/by-name/boot$SLOT $BOOT

echo "* Unpacking boot$SLOT"
rm boot-new.img header kernel ramdisk.cpio >/dev/null 2>&1
magiskboot unpack -h $BOOT >/dev/null 2>&1

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

magiskboot cpio ramdisk.cpio "rm overlay.d/joshuax.rc" >/dev/null 2>&1 #v1.0.0

echo "* Repacking boot$SLOT"
magiskboot repack $BOOT boot-new.img
rm header kernel ramdisk.cpio

echo "* Flashing boot$SLOT"
cp boot-new.img /dev/block/bootdevice/by-name/boot$SLOT

echo "* Cleaning up"
rm boot.img boot-new.img header kernel ramdisk.cpio
rm -rf META-INF

echo "* Installing service"
rm /data/adb/service.d/joshuax.sh #v1.0.0
rm /data/adb/post-fs-data.d/joshuax.sh #v1.0.0
cp service.sh /data/adb/service.d/ptune.sh
ln -s /data/adb/service.d/ptune.sh /data/adb/post-fs-data.d/ptune.sh

echo "* Syncing"
sync
