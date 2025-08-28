#!/system/bin/sh

LOGFILE="/cache/ptune.log"

#MODDIR=${0%/*}
DIRSH="$(dirname $0)"
DIRBIN="$DIRSH/bin"

PATH="$DIRBIN:$PATH"

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSG=$VS/groups
FREQ=/sys/devices/system/cpu/cpufreq
MM=/sys/kernel/mm
THP=$MM/transparent_hugepage

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

logwipe() {
  rm -f "$LOGFILE"
}

log() {
  ls="($DIRSH) ptune: $1"
  echo "$ls" >> "$LOGFILE"
  echo "$ls"
}

ptune() {

cpuf="$(cat $CS/cpus)"

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
schedgroup bg        0    1024 0 1 1 #0     512
schedgroup cam       0    1024 0 1 0 #1    1024
schedgroup cam_power 0    1024 0 1 0 #0    1024
schedgroup dex2oat   0    1024 0 1 0 #0     615
schedgroup fg        0    1024 0 1 0 #0    1024
schedgroup fg_wi     0    1024 0 1 0 #0    1024
schedgroup nnapi     0    1024 0 1 0 #225  1024
schedgroup ota       0    1024 0 1 0 #0     512
schedgroup rt        0    1024 0 1 0 #0    1024
schedgroup sf        0    1024 0 1 0 #0    1024
schedgroup sys       0    1024 0 1 0 #0    1024
schedgroup sys_bg    0    1024 0 1 0 #0     512
schedgroup ta        0    1024 0 1 0 #1    1024

# cpuset | cpus
cpuset background                   "$cpuf" #0-3
cpuset camera-daemon                "$cpuf" #0-7
cpuset camera-daemon-high-group     6-7     #6-7
cpuset camera-daemon-mid-group      4-5     #4-5
cpuset camera-daemon-mid-high-group 4-7     #4-7
cpuset foreground                   "$cpuf" #0-5
cpuset foreground_window            "$cpuf" #0-5
cpuset restricted                   0-3     #0-3
cpuset system                       "$cpuf" #0-7 (custom, !sys)
cpuset system-background            "$cpuf" #0-3
cpuset top-app                      "$cpuf" #0-7

# Give our CPU a lunch break when it wants one
# down delay | up delay
delayfreqs 0 0 #5000 0

# adpf rampup multiplier
# latency in nanoseconds
# reduce prefer idle
sched 1 8333333 0 #2 8000000 0

# Speed up disk access
# async depth
# scheduler
blocksched sda mq-deadline 100 16384 #62 62
blocksched sdb mq-deadline 100 16384 #62 62
blocksched sdc mq-deadline 100 16384 #62 62
blocksched sdd mq-deadline 100 16384 #62 62

# Adjust our kernel's tunables
echo 0 > $VM/dirty_writeback_centisecs
echo 0 > $VM/swappiness
echo 1 > $VM/vfs_cache_pressure
echo 1 > $KR/sched_child_runs_first
echo within_size > $THP/shmem_enabled
echo always > $THP/defrag
echo always > $THP/enabled

# Allow swap to reach 99% before triggering LMKD
resetprop -n ro.lmk.swap_free_low_percentage 1

# Disable SurfaceFlinger frame dropping, no but for real
resetprop -d debug.sf.use_phase_offsets_as_durations #1
resetprop -d debug.sf.late.sf.duration               #10500000
resetprop -d debug.sf.late.app.duration              #16600000
resetprop -d debug.sf.early.sf.duration              #16600000
resetprop -d debug.sf.early.app.duration             #16600000
resetprop -d debug.sf.earlyGl.sf.duration            #16600000
resetprop -d debug.sf.earlyGl.app.duration           #16600000
resetprop -d debug.sf.frame_rate_multiple_threshold  #120

# Raise the frequency of sampling regions in SurfaceFlinger
resetprop -n debug.sf.region_sampling_duration_ns      8333333  #unset
resetprop -n debug.sf.region_sampling_period_ns        99999984 #unset
resetprop -n debug.sf.region_sampling_timer_timeout_ns 99999984 #unset

}

zram() {
  local gigs=${1:-1}

  log "Dumping zram:"
  zramcfg >> "$LOGFILE"

  local kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  local zramB=$(awk -v kb="$kb" -v g="$gigs" 'BEGIN{printf "%.0f\n", kb*1024 - g*1073741824}')
  local sizeTxt=$(awk -v kb="$kb" 'BEGIN{print int(kb/1048576)+1}')
  local zramTxt=$(awk -v b="$zramB" 'BEGIN{print int(b/1073741824)+1}')

  log "Resizing ZRAM to ${zramTxt}/${sizeTxt}GB"
  zramcfg -s "$zramB" >> "$LOGFILE"
}

#########

logwipe

log "Setting initial boot values"
ptune

# Avoid waiting to finalize values if we're already through init's boot sequence
if [ "$(bootcomplete)" == "1" ]; then
  zram

  log "No need to finalize new values"
  exit 0
fi

# Restart SurfaceFlinger to take in the new values
## Unfortunately increases boot time, need to set earlier in init before SF
log "Restarting SurfaceFlinger with force"
killall -9 surfaceflinger

log "Waiting for boot complete"
while [ "$(bootcomplete)" != "1" ]; do sleep 1; done

zram

log "Finalizing values"
ptune

log "Pixel Tune is done!"
