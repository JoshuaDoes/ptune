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
magiskboot unpack -h $BOOT

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
  magiskboot cpio ../ramdisk.cpio "mkdir 0700 $DIR" >/dev/null 2>&1
done
for f in $(find . -type f)
do
  FILE="${f#./}"
  echo "- $FILE"
  magiskboot cpio ../ramdisk.cpio "add 0777 $FILE $FILE" >/dev/null 2>&1
done
unset IFS; set +f
cd ..

magiskboot cpio ramdisk.cpio "rm overlay.d/joshuax.rc" #v1.0.0

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
cp service.sh /data/adb/service.d/ptune.sh

echo "* Syncing"
sync
