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
BOOT=boot
if [ -b "/dev/block/bootdevice/by-name/init_boot$SLOT" ]; then
  BOOT=init_boot
fi

cd "$MODDIR"

if [ -d "$MODDIR/ramdisk" ]; then
  chmod +x "$MODDIR/bin/magiskboot"

  echo "* Copying $BOOT$SLOT"
  cp /dev/block/bootdevice/by-name/$BOOT$SLOT $BOOT.img

  echo "* Unpacking $BOOT$SLOT"
  rm $BOOT-new.img header kernel ramdisk.cpio >/dev/null 2>&1
  magiskboot unpack -h $BOOT.img

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

  echo "* Repacking $BOOT$SLOT"
  magiskboot repack $BOOT.img $BOOT-new.img
  rm header kernel ramdisk.cpio

  echo "* Flashing $BOOT$SLOT"
  cp $BOOT-new.img /dev/block/bootdevice/by-name/$BOOT$SLOT

  echo "* Cleaning up"
  rm $BOOT.img $BOOT-new.img header kernel ramdisk.cpio
  rm -rf META-INF
#else #TEST: Preserve the module if we fail to detect the ramdisk path
#  cp -R "$MODDIR" "/data/adb/modules_update/ptune"
#  reboot now
fi

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
