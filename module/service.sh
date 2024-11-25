#!/system/bin/sh

#MODDIR=${0%/*}
SHDIR="$(dirname $0)"
MAGISKPFDD=/dev/adb/post-fs-data.d
MAGISKSD=/dev/adb/service.d

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSG=$VS/groups

blocksched() {
  bs="/sys/block/$2/queue/scheduler"
  chmod 200 "$bs"
  echo "$1" > "$bs"
}

perfsched() {
  g="$VSG/$4"
  chmod 200 "$g/prefer_high_cap"
  chmod 200 "$g/prefer_idle"
  chmod 200 "$g/uclamp_max"
  echo "$1" > "$g/uclamp_max"
  echo "$2" > "$g/prefer_high_cap"
  echo "$3" > "$g/prefer_idle"
}

# Wait for successful boot to run the rest
if [ "$SHDIR" == "$MAGISKPFDD" ]; then
  echo "Waiting for boot completed"
  while [ "$(getprop sys.boot_completed | tr -d '\r')" != "1" ]; do sleep 1; done
fi

# Adjust our kernel's tunables
echo 0 > $VM/dirty_writeback_centisecs
echo 1 > $VM/swappiness
echo 5 > $VM/vfs_cache_pressure
echo 0 > $KR/sched_child_runs_first

# Speed up disk access
blocksched none sda
blocksched none sdb
blocksched none sdc
blocksched none sdd

# Allow vendor scheduler groups to migrate to any core if cpuset allows
echo "2048 2048 2048" > $VS/util_threshold

# Prefer running on big versus prefer to idle
perfsched 1024 1 0 cam
perfsched 1024 0 0 cam_power
perfsched 1024 0 1 dex2oat
perfsched 1024 0 1 fg
perfsched 1024 0 1 ota
perfsched 1024 1 1 rt
perfsched 1024 1 1 sf
perfsched 1024 1 1 sys
perfsched 1024 0 1 ta

# Disable SurfaceFlinger frame dropping, no but for real
resetprop -d debug.sf.use_phase_offsets_as_durations
resetprop -d debug.sf.late.sf.duration
resetprop -d debug.sf.late.app.duration
resetprop -d debug.sf.early.sf.duration
resetprop -d debug.sf.early.app.duration
resetprop -d debug.sf.earlyGl.sf.duration
resetprop -d debug.sf.earlyGl.app.duration
resetprop -d debug.sf.frame_rate_multiple_threshold

# Allow swap to reach 95% before triggering low memory killer
resetprop -n ro.lmk.swap_free_low_percentage 5

if [ "$SHDIR" == "$MAGISKSD" ]; then
  exit 0
elif [ "$SHDIR" == "$MAGISKPFDD" ]; then
  # Save the boot log!
  logcat -b all > /data/adb/logcat.log
fi
