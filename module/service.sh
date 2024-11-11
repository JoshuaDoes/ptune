#!/system/bin/sh

#MODDIR=${0%/*}

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSG=$VS/groups
CF=/sys/devices/system/cpu/cpufreq

# Wait for successful boot
while [ "$(getprop sys.boot_completed | tr -d '\r')" != "1" ]; do sleep 1; done

# Adjust our kernel's tunables
echo 0 > $VM/dirty_writeback_centisecs
echo 1 > $VM/swappiness
echo 5 > $VM/vfs_cache_pressure
echo 1 > $KR/sched_child_runs_first

## top-app
echo "0-7" > $CS/top-app/cpus
echo "0-8" > $CS/top-app/cpus

## system
echo "0-7" > $CS/system/cpus
echo "0-8" > $CS/system/cpus

# Allow vendor scheduler groups to migrate to any core if cpuset allows
chmod 200 $VS/util_threshold
chmod 200 $VSG/cam/prefer_high_cap
chmod 200 $VSG/cam/uclamp_max
chmod 200 $VSG/cam_power/prefer_high_cap
chmod 200 $VSG/cam_power/uclamp_max
chmod 200 $VSG/dex2oat/prefer_high_cap
chmod 200 $VSG/dex2oat/uclamp_max
chmod 200 $VSG/fg/prefer_high_cap
chmod 200 $VSG/fg/uclamp_max
chmod 200 $VSG/ota/prefer_high_cap
chmod 200 $VSG/ota/uclamp_max
chmod 200 $VSG/rt/prefer_high_cap
chmod 200 $VSG/rt/uclamp_max
chmod 200 $VSG/sf/prefer_high_cap
chmod 200 $VSG/sf/uclamp_max
chmod 200 $VSG/sys/prefer_high_cap
chmod 200 $VSG/sys/uclamp_max
chmod 200 $VSG/ta/prefer_high_cap
chmod 200 $VSG/ta/uclamp_max

echo "2048 2048 2048" > $VS/util_threshold
echo 1 > $VSG/cam/prefer_high_cap
echo 1024 > $VSG/cam/uclamp_max
echo 1 > $VSG/cam_power/prefer_high_cap
echo 1024 > $VSG/cam_power/uclamp_max
echo 0 > $VSG/dex2oat/prefer_high_cap
echo 1024 > $VSG/dex2oat/uclamp_max
echo 1 > $VSG/fg/prefer_high_cap
echo 1024 > $VSG/fg/uclamp_max
echo 0 > $VSG/ota/prefer_high_cap
echo 1024 > $VSG/ota/uclamp_max
echo 1 > $VSG/rt/prefer_high_cap
echo 1024 > $VSG/rt/uclamp_max
echo 1 > $VSG/sf/prefer_high_cap
echo 1024 > $VSG/sf/uclamp_max
echo 1 > $VSG/sys/prefer_high_cap
echo 1024 > $VSG/sys/uclamp_max
echo 0 > $VSG/ta/prefer_high_cap
echo 1024 > $VSG/ta/uclamp_max

# Pace frames at 120Hz, minimum 60Hz when SF is late
resetprop -n debug.sf.early.app.duration 8333333
resetprop -n debug.sf.early.sf.duration 8333333
resetprop -n debug.sf.earlyGl.app.duration 8333333
resetprop -n debug.sf.earlyGl.sf.duration 8333333
resetprop -n debug.sf.late.app.duration 8333333
resetprop -n debug.sf.late.sf.duration 8333333

# Allow swap to reach 100% before triggering low memory killer
resetprop -n ro.lmk.swap_free_low_percentage 0
