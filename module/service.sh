#!/system/bin/sh

#MODDIR=${0%/*}
SHDIR="$(dirname $0)"
MAGISKSD=/dev/adb/service.d
MAGISKPFDD=/dev/adb/post-fs-data.d

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSG=$VS/groups
FREQ=/sys/devices/system/cpu/cpufreq

F0=$FREQ/policy0
F1=$FREQ/policy4
F2=$FREQ/policy6
FS0=$F0/sched_pixel
FS1=$F1/sched_pixel
FS2=$F2/sched_pixel
FD0=$FS0/down_rate_limit_us
FD1=$FS1/down_rate_limit_us
FD2=$FS2/down_rate_limit_us
FU0=$FS0/up_rate_limit_us
FU1=$FS1/up_rate_limit_us
FU2=$FS2/up_rate_limit_us

blocksched() {
  depth="/sys/block/$1/queue/iosched/async_depth"
  nrreq="/sys/block/$1/queue/nr_requests"
  sched="/sys/block/$1/queue/scheduler"
  chmod 200 "$depth"
  chmod 200 "$nrreq"
  chmod 200 "$sched"
  echo "$2" > "$sched"
  echo "$3" > "$nrreq"
  echo "$4" > "$depth"
}

schedgroup() {
  g="$VSG/$1"
  umi="$g/uclamp_min"
  uma="$g/uclamp_max"
  phc="$g/prefer_high_cap"
  pi="$g/prefer_idle"
  ts="$g/task_spreading"
  chmod 200 "$umi"
  chmod 200 "$uma"
  chmod 200 "$phc"
  chmod 200 "$pi"
  chmod 200 "$ts"
  echo "$2" > "$umi"
  echo "$3" > "$uma"
  echo "$4" > "$phc"
  echo "$5" > "$pi"
  echo "$6" > "$ts"
}

sched() {
  ramp="$VS/adpf_rampup_multiplier"
  lat="$VS/latency_ns"
  rpi="$VS/reduce_prefer_idle"
  chmod 200 "$ramp"
  chmod 200 "$lat"
  chmod 200 "$rpi"
  echo "$1" > "$ramp"
  echo "$2" > "$lat"
  echo "$3" > "$rpi"
}

delayfreqs() {
  for down in "$FD0" "$FD1" "$FD2"; do
    echo $1 > "$down"
  done
  for up in "$FU0" "$FU1" "$FU2"; do
    echo $2 > "$up"
  done
}

cpuset() {
  cs="$CS/$1"
  echo "$2" > "$cs/cpus"
}

bootcomplete() {
  echo $(getprop sys.boot_completed | tr -d '\r')
}

#########

ptune() {

# Allow vendor scheduler groups to fully utilize cores
echo "2048 2048 2048 2048 2048 2048 2048 2048" > $VS/util_threshold

## uclamp max ##
# LITTLE = 158
#    MID = 490
#    BIG = 1024
################
# group
# uclamp min
# uclamp max
# prefer big
# prefer idle
# task spread
schedgroup bg        0     158 0 1 1 #0 158
schedgroup cam       0    1024 0 0 0 #0 1024 (?¿?)
schedgroup cam_power 0    1024 0 0 0 #0 1024 (?¿?)
schedgroup dex2oat   0    1024 0 1 0 #0 1024 (?¿?)
schedgroup fg        0     490 0 1 0 #0 490
schedgroup fg_wi     0    1024 0 1 0 #0 757 (?¿?)
schedgroup nnapi     0    1024 0 1 0 #0 1024 (?¿?)
schedgroup ota       0    1024 0 1 0 #0 1024 (?¿?)
schedgroup rt        0     158 0 1 1 #0 158
schedgroup sf        0     158 0 1 1 #0 490 (?¿?)
schedgroup sys       0    1024 0 1 0 #0 490 (?¿?)
schedgroup sys_bg    0     158 0 1 1 #0 158
schedgroup ta        0    1024 0 1 0 #0 1024

# cpuset | cpus
cpuset background                   0-3 #0-3
cpuset camera-daemon                0-7 #0-7 (?¿?)
cpuset camera-daemon-high-group     6-7 #0-7 (?¿?)
cpuset camera-daemon-mid-group      4-5 #0-7 (?¿?)
cpuset camera-daemon-mid-high-group 4-7 #0-7 (?¿?)
cpuset foreground                   0-5 #0-5
cpuset foreground_window            0-7 #0-6
cpuset restricted                   0-3 #0-3
cpuset system                       0-7 #0-7 (custom, !sys)
cpuset system-background            0-3 #0-3
cpuset top-app                      0-7 #0-7

# Give our CPU a lunch break when it wants one
delayfreqs 0 0 #5000 0

# adpf rampup multiplier
# latency in nanoseconds
# reduce prefer idle
sched 1 4166666 1 #2 8000000 1

# Speed up disk access
# async depth
# scheduler
blocksched sda mq-deadline 100 16384 #62 62
blocksched sdb mq-deadline 100 16384 #62 62
blocksched sdc mq-deadline 100 16384 #62 62
blocksched sdd mq-deadline 100 16384 #62 62

# Adjust our kernel's tunables
echo 0 > $VM/dirty_writeback_centisecs
echo 1 > $VM/swappiness
echo 5 > $VM/vfs_cache_pressure
echo 1 > $KR/sched_child_runs_first

# Allow swap to reach 97% before triggering low memory killer
resetprop -n ro.lmk.swap_free_low_percentage 3

# Disable SurfaceFlinger frame dropping, no but for real
resetprop -d debug.sf.use_phase_offsets_as_durations
resetprop -d debug.sf.late.sf.duration
resetprop -d debug.sf.late.app.duration
resetprop -d debug.sf.early.sf.duration
resetprop -d debug.sf.early.app.duration
resetprop -d debug.sf.earlyGl.sf.duration
resetprop -d debug.sf.earlyGl.app.duration
resetprop -d debug.sf.frame_rate_multiple_threshold

}

#########

case "$SHDIR" in
  "$MAGISKPFDD")
    echo "ptune: Waiting for boot complete"
    while [ bootcomplete != "1" ]; do sleep 1; done
    break;;
  "$MAGISKSD")
    echo "ptune: Initial boot"
    break;;
  *)
    echo "ptune: Running unconditionally"
esac

ptune
