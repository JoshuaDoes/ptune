#!/system/bin/sh
export MODDIR="/data/adb/modules/ptune"
if [ ! -d "$MODDIR" ]; then
  MODDIR="/data/adb/modules_update/ptune"
  if [ ! -d "$MODDIR" ]; then
    echo "Could not locate MODDIR!"
    exit 1
  fi
fi

PATH="$MODDIR/bin:$PATH"
SLOT="$(getprop | grep ro.boot.slot_suffix | sed -e 's/.*: \[\(.*\)\].*/\1/')"
BOOT=boot.img

cd "$MODDIR"
chmod +x "$MODDIR/bin/magiskboot"

echo "* Copying boot$SLOT"
cp /dev/block/bootdevice/by-name/boot$SLOT boot.img

echo "* Unpacking boot$SLOT"
rm boot-new.img header kernel ramdisk.cpio >/dev/null 2>&1
magiskboot unpack -h $BOOT

echo "* Restoring ramdisk"
cd ramdisk
IFS=$'\n'; set -f
for f in $(find . -type f)
do
  FILE="${f#./}"
  echo "- $FILE"
  magiskboot cpio ../ramdisk.cpio "rm $FILE" >/dev/null 2>&1
done
#for d in $(find . -type d)
#do
#  if [ $d == "." ]; then
#    continue
#  fi
#  DIR="${d#./}"
#  echo "- $DIR"
#  ## This will fail successfully for non-empty folders
#  magiskboot cpio ../ramdisk.cpio "rm $DIR" >/dev/null 2>&1
#done
unset IFS; set +f
cd ..

echo "* Repacking boot$SLOT"
magiskboot repack $BOOT boot-new.img
rm header kernel ramdisk.cpio

echo "* Flashing boot$SLOT"
cp boot-new.img /dev/block/bootdevice/by-name/boot$SLOT

echo "* Cleaning up"
rm boot.img boot-new.img header kernel ramdisk.cpio
rm -rf META-INF

echo "* Removing service"
rm /data/adb/service.d/ptune.sh
rm /data/adb/post-fs-data.d/ptune.sh

echo "* Obliterating module"
rm -rf /data/adb/modules/ptune
rm -rf /data/adb/modules_update/ptune

echo "* Syncing"
sync

echo "* Rebooting to finalize uninstall"
reboot now
