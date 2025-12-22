## <<< Shamelessly borrowed from Magisk
set_perm() {
  chown $2:$3 $1 || return 1
  chmod $4 $1 || return 1
  local CON=$5
  [ -z $CON ] && CON=u:object_r:system_file:s0
  chcon $CON $1 || return 1
}
set_perm_recursive() {
  find $1 -type d 2>/dev/null | while read dir; do
    set_perm $dir $2 $3 $4 $6
  done
  find $1 -type f -o -type l 2>/dev/null | while read file; do
    set_perm $file $2 $3 $5 $6
  done
}
## >>>

echo ""
echo "Installing: Pixel Tune v1.7.2"
echo ""

#SLOT="$(getprop | grep ro.boot.slot_suffix | sed -e 's/.*: \[\(.*\)\].*/\1/')"
BOOT=boot
if [ -b "/dev/block/bootdevice/by-name/init_boot_a" ]; then
  BOOT=init_boot
fi

PATH="$MODDIR/bin:$PATH"
cd "$MODDIR"

set_perm_recursive "$MODDIR" 0 0 0755 0644
chmod +x "$MODDIR/bin/magiskboot"
chmod +x "$MODDIR/bin/ptuneinitrc"
chmod +x "$MODDIR/bin/zramcfg"
chmod +x "$MODDIR/service.sh"

BOARD="$(getprop ro.board.platform)"
DEVICE="$(getprop ro.product.device)"
RELEASE="$(getprop ro.build.version.release_or_codename)"
FINGERPRINT="$(getprop ro.build.fingerprint)"

RAMDISK="$MODDIR/ramdisk"
RCD="$RAMDISK/overlay.d"
RC="$RCD/ptune.rc"
RCS="$MODDIR/initrc"
RD="$MODDIR/system"
RDS="$MODDIR/systems"
TARGETS="$RELEASE $BOARD $DEVICE $RELEASE.$BOARD $RELEASE.$DEVICE $BOARD.$DEVICE $RELEASE.$BOARD.$DEVICE $FINGERPRINT"

echo "* Generating initrc patches for $FINGERPRINT"
mkdir -p "$RCS/$(dirname $FINGERPRINT)"
PTUNEINIT="$RCS/$FINGERPRINT.rc"
ptuneinitrc > "$PTUNEINIT"
if [ ! -s "$PTUNEINIT" ]; then
  echo "! No initrc patches generated!"
  rm "$$PTUNEINIT"
fi
echo ""

for target in $TARGETS; do
  t="$RCS/$target.rc"
  r="$RDS/$target"
  if [ -f "$t" ]; then
    echo "+ initrc: $target"
    mkdir -p "$RCD"
    cat "$t" >> "$RC"
  fi
  if [ -d "$r" ]; then
    echo "+ system: $target"
    mkdir -p "$RD"
    cp -R "$r"/* "$RD/"
  fi
done
if [ ! -f "$RC" ]; then
  echo "! No initrc patches found! Installing as service only..."
fi
echo ""

if [ -d "$RAMDISK" ]; then
  for slot in $(find /dev/block/bootdevice/by-name -type l -name "$BOOT"'_*'); do
    SLOT=$(basename "$slot")

    echo "* Copying $SLOT"
    cp /dev/block/bootdevice/by-name/$SLOT $BOOT.img

    echo "* Unpacking $SLOT"
    rm $BOOT-new.img header kernel ramdisk.cpio >/dev/null 2>&1
    magiskboot unpack -h $BOOT.img >/dev/null 2>&1

    if [ ! -f ramdisk.cpio ]; then
      echo "! Skipping $SLOT due to missing ramdisk"
      continue
    fi

    echo "* Adjusting ramdisk"
    cd ramdisk
    IFS=$'\n'; set -f
    for d in $(find . -type d)
    do
      if [ $d == "." ]; then
        continue
      fi
      DIR="${d#./}"
      echo "+ $DIR/"
      magiskboot cpio ../ramdisk.cpio "mkdir 0777 $DIR" >/dev/null 2>&1
    done
    for f in $(find . -type f)
    do
      FILE="${f#./}"
      echo "+ $FILE"
      magiskboot cpio ../ramdisk.cpio "rm $FILE" >/dev/null 2>&1
      magiskboot cpio ../ramdisk.cpio "add 0777 $FILE $FILE" >/dev/null 2>&1
    done
    unset IFS; set +f
    cd ..

    echo "* Repacking $SLOT"
    magiskboot repack $BOOT.img $BOOT-new.img
    rm header kernel ramdisk.cpio

    echo "* Flashing $SLOT"
    cp $BOOT-new.img /dev/block/bootdevice/by-name/$SLOT

    echo "* Cleaning up"
    rm $BOOT.img $BOOT-new.img header kernel ramdisk.cpio
    rm -rf META-INF

    echo "* Syncing"
    sync

    echo ""
  done
fi

echo "* Reboot to finish install!"
