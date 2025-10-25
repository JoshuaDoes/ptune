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

hide() {
  command "$@" >/dev/null 2>&1
}

lock() {
  if [ $# -lt 1 ]; then return; fi
  hide chown root:root "$1"
  if [ $# -gt 1 ]; then
    hide chmod 200 "$1"
    echo "$2" > "$1"
  fi
  hide chmod 000 "$1"
}

powervr_sched() {
  gpu="/sys/class/devfreq/34f00000.gpu0"
  poll="$gpu/polling_interval"
  #af="$gpu/available_frequencies"
  mif="$gpu/min_freq"
  maf="$gpu/max_freq"
  tf="$gpu/target_freq"
  vm="$gpu/vote_manager"

  lock "$poll" $1

  min=198000000
  max=1094000000
  lock "$mif" $min
  lock "$maf" $max
  lock "$tf" $min
  lock "$vm/soft_min_freq" $min
  lock "$vm/soft_max_freq" $max
}

blocksched() {
  for block in /sys/block/sd*; do
    lock "$block/queue/scheduler" $1
    lock "$block/queue/nr_requests" $2
    lock "$block/queue/iosched/async_depth" $3
  done
}

schedgroup() {
  g="$VSG/$1"
  umi="$g/uclamp_min"
  uma="$g/uclamp_max"
  phc="$g/prefer_high_cap"
  pi="$g/prefer_idle"
  ts="$g/task_spreading"
  lock "$umi" $2
  lock "$uma" $3
  lock "$phc" $4
  lock "$pi" $5
  lock "$ts" $6
}

sched() {
  ramp="$VS/adpf_rampup_multiplier"
  rpi="$VS/reduce_prefer_idle"
  api="$VS/auto_prefer_idle"
  lat="$VS/latency_ns"
  mg="$VS/min_granularity_ns"

  lock "$ramp" $1
  lock "$rpi" $2
  lock "$api" $2
  if [ -f "$lat" ]; then lock "$lat" $3; fi #rip laguna
  if [ -f "$mg" ]; then lock "$mg" $3; fi
  for policy in $FREQ/*; do
    sp="$policy/sched_pixel"
    cbl="$sp/cpu_busy_limit_ms"
    rtms="$sp/response_time_ms"
    if [ -f "$cbl" ]; then lock "$cbl" $4; fi
    if [ -f "$rtms" ]; then lock "$rtms" $4; fi
  done
}

delayfreqs() {
  for policy in $FREQ/*; do
    if [ -d "$policy/sched_pixel" ]; then
      lock "$policy/sched_pixel/down_rate_limit_us" $1
      lock "$policy/sched_pixel/up_rate_limit_us" $2
    fi
    if [ -d "$policy/vote_manager" ]; then #laguna
      vm="$policy/vote_manager"
      lock "$vm/soft_min_freq" $(cat "$policy/cpuinfo_min_freq")
      lock "$vm/soft_max_freq" $(cat "$policy/cpuinfo_max_freq")
    fi
  done
}

cpuset() {
  cs="$CS/$1"
  if [ -d "$cs" ]; then lock "$cs/cpus" "$2"; fi
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
lock $VS/util_threshold            9999 #?
lock $VS/auto_uclamp_max           1024 #130 130 512 512 512 512 512 670
lock $VS/auto_dvfs_headroom_enable 0    #0=off, 1=on
lock $VS/dvfs_headroom             1280 #1100

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

# Pixel CPUFreq scheduler rate
# adpf rampup multiplier
# reduce prefer idle
# latency in nanoseconds
# latency in milliseconds, combo of cpu_busy_limit_ms (default 10) and response_time_ms (default 14)
sched 1 0 8333333 8 #2 8000000 0

# PowerVR GPU scheduling rate in milliseconds
powervr_sched 8 #20

# Speed up disk access
# scheduler
# number of requests
# async depth
#blocksched mq-deadline 100 16384 #mq-deadline 62 62
blocksched mq-deadline 500 20000 #mq-deadline 62 62

# Adjust our kernel's tunables
lock $VM/dirty_writeback_centisecs 0
lock $VM/swappiness                0
lock $VM/vfs_cache_pressure        1
lock $THP/shmem_enabled            within_size
lock $THP/defrag                   always
lock $THP/enabled                  always

# Adjust kernel tunables that still exist
if [ -f "$VM/sched_child_runs_first" ]; then lock $VM/sched_child_runs_first 1; fi

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

# Raise the amount of SurfaceFlinger layers that HWC should track
resetprop -n ro.surface_flinger.max_frame_buffer_acquired_buffers 7 #3

# Disable limiting the maximum frame rate for games at 60Hz
resetprop -n debug.graphics.game_default_frame_rate.disabled true #unset

}

zram() {
  local gigs=${1:-1}

  log "Dumping zram:"
  log "$(zramcfg)"

  local kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  local zramB=$(awk -v kb="$kb" -v g="$gigs" 'BEGIN{printf "%.0f\n", kb*1024 - g*1073741824}')
  local sizeTxt=$(awk -v kb="$kb" 'BEGIN{print int(kb/1048576)+1}')
  local zramTxt=$(awk -v b="$zramB" 'BEGIN{print int(b/1073741824)+1}')

  log "Resizing ZRAM to ${zramTxt}/${sizeTxt}GB"
  log "$(zramcfg -s $zramB)"
}

#########

if [ -f "$DIRSH/debug" ]; then
  # Start logging in case of early init failure
  logcat > /cache/logcat.log &
fi

logwipe

log "Setting initial boot values"
ptune

# Avoid waiting to finalize values if we're already through init's boot sequence
if [ "$(bootcomplete)" -eq "1" ]; then
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
