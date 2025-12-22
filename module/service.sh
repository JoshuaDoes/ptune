#!/system/bin/sh

version() {
  echo "Pixel Tune v1.7.2"
}
platform() {
  getprop ro.board.platform
}
brand() {
  getprop ro.product.brand
}
device() {
  getprop ro.product.device
}

#MODDIR=${0%/*}
DIRSH="$(dirname $0)"
DIRBIN="$DIRSH/bin"

PATH="$DIRBIN:$PATH"
LOGFILE="/cache/ptune.log"

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSG=$VS/groups
FREQ=/sys/devices/system/cpu/cpufreq
MM=/sys/kernel/mm
THP=$MM/transparent_hugepage

logwipe() {
  rm -f "$LOGFILE"
}

log() {
  ls="($DIRSH) ptune: $1"
  echo "$ls" >> "$LOGFILE"
  echo "$ls"
}

hide() {
  command "$@" >>"$LOGFILE" 2>&1
}

lock() {
  if [ $# -lt 1 ]; then return; fi
  if [ ! -f "$1" ]; then return; fi
  chown root:root "$1"
  #hide chown root:root "$1"
  if [ $# -gt 1 ]; then
    chmod 200 "$1"
    #hide chmod 200 "$1"
    echo "$2" > "$1"
  fi
  chmod 000 "$1"
  #hide chmod 000 "$1"
}

powervr_sched() {
  gpu="/sys/class/devfreq/34f00000.gpu0"
  poll="$gpu/polling_interval"
  #af="$gpu/available_frequencies"
#  mif="$gpu/min_freq"
  maf="$gpu/max_freq"
#  tf="$gpu/target_freq"
  vm="$gpu/vote_manager"

  lock "$poll" $1

  min=0
  max=9999999999

#  lock "$mif" $min
  lock "$maf" $max
#  lock "$tf" $min
#  lock "$vm/soft_min_freq" $min
#  lock "$vm/soft_min_freq" $max
  lock "$vm/soft_max_freq" $max
}

mali_sched() {
  gpu="/sys/devices/platform/1c500000.mali"
  dvfs="$gpu/dvfs_period"
  #af="$gpu/available_frequencies"
  mif="$gpu/min_freq"
  maf="$gpu/max_freq"
  hmif="$gpu/hint_min_freq"
  hmaf="$gpu/hint_max_freq"
  smif="$gpu/scaling_min_freq"
  smicf="$gpu/scaling_min_compute_freq"
  smaf="$gpu/scaling_max_freq"

  lock "$dvfs" $1
  #echo $1 > "$dvfs"

  #TODO: Automatic min/max
  min=0
  max=9999999

#  lock "$mif" $min
  lock "$maf" $max
#  lock "$hmif" $min
  lock "$hmaf" $max
#  lock "$smif" $min
#  lock "$smicf" $min
  lock "$smaf" $max
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
  lock "$lat" $3 #rip laguna
  lock "$mg" $3
  for policy in $FREQ/*; do
    sp="$policy/sched_pixel"
    cbl="$sp/cpu_busy_limit_ms"
    rtms="$sp/response_time_ms"
    lock "$cbl" $4
    lock "$rtms" $4
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
#      lock "$vm/soft_min_freq" $(cat "$policy/cpuinfo_max_freq")
      lock "$vm/soft_max_freq" $(cat "$policy/cpuinfo_max_freq")
    fi
  done
}

cpuset() {
  cs="$CS/$1"
  if [ -d "$cs" ]; then echo "$2" > "$cs/cpus"; fi
}

bootcomplete() {
  getprop sys.boot_completed | tr -d '\r'
}

###########################################################################################
# Shamelessly stolen from github.com/yinwanxi/Uperf-Game-Turbo@f8346a4 to disable Ximi shit
###########################################################################################
lock_val() {
  lock "$2" "$1"
}
mask_val() {
  touch /data/local/tmp/mount_mask
  for p in $2; do
    if [ -f "$p" ]; then
      umount "$p"
      chmod 0666 "$p"
      echo "$1" > "$p"
      mount --bind /data/local/tmp/mount_mask "$p"
    fi
  done
}
hide_value() {
  if [[ -e "$1" ]]; then
    umount "$1" 2>/dev/null
    c_path="/cache${1}"
    if [[ ! -f "$c_path" ]]; then
      mkdir -p "$c_path"
      rm -r "$c_path"
    fi
    chattr -i "$c_path"
    cp -f "$1" "$c_path"
    if [[ "$2" != "" ]]; then
      lock_value "$2" "$1"
    fi
    mount --bind "$c_path" "$1"
  else
    echo "$1 not found!"
  fi
}

disable_kernel_boost() {
    # Qualcomm
    lock_val "0" "/sys/devices/system/cpu/cpu_boost/*"
    lock_val "0" "/sys/devices/system/cpu/cpu_boost/parameters/*"
    lock_val "0" "/sys/module/cpu_boost/parameters/*"
    lock_val "0" "/sys/module/msm_performance/parameters/*"
    lock_val "0" "/sys/kernel/msm_performance/parameters/*"
    lock_val "0" "/proc/sys/walt/input_boost/*"
    # 3rd
    lock_val "0" "/sys/kernel/cpu_input_boost/*"
    lock_val "0" "/sys/module/cpu_input_boost/parameters/*"
    lock_val "0" "/sys/module/dsboost/parameters/*"
    lock_val "0" "/sys/module/devfreq_boost/parameters/*"
}
set_corectl_param() {
    local key
    local val
    for kv in $2; do
        key=${kv%:*}
        val=${kv#*:}
        lock_val "$val" /sys/devices/system/cpu/cpu$key/core_ctl/$1
    done
}
disable_hotplug() {
    # turn off msm_thermal
    lock_val "0" /sys/module/msm_thermal/core_control/enabled
    lock_val "N" /sys/module/msm_thermal/parameters/enabled
    # 3rd
    lock_val "0" /sys/kernel/intelli_plug/intelli_plug_active
    lock_val "0" /sys/module/blu_plug/parameters/enabled
    lock_val "0" /sys/devices/virtual/misc/mako_hotplug_control/enabled
    lock_val "0" /sys/module/autosmp/parameters/enabled
    lock_val "0" /sys/kernel/zen_decision/enabled
    # stop sched core_ctl
    set_corectl_param "enable" "0:0 6:0 7:0"
    # bring all cores online
    for i in 0 1 2 3 4 5 6 7 8 9; do
        lock_val "1" /sys/devices/system/cpu/cpu$i/online
    done
}
change_task_cgroup() {
    local comm
    for temp_pid in $(echo "$ps_ret" | grep -i -E "$1" | awk '{print $1}'); do
        for temp_tid in $(ls "/proc/$temp_pid/task/"); do
            comm="$(cat /proc/$temp_pid/task/$temp_tid/comm)"
            echo "$temp_tid" >"/dev/$3/$2/tasks"
        done
    done
}
unify_cgroup() {
    # clear top-app
    for p in $(cat /dev/cpuset/top-app/tasks); do
        echo $p >/dev/cpuset/foreground/tasks
    done
    # unused
    rmdir /dev/cpuset/foreground/boost
    # work with uperf/ContextScheduler
    change_task_cgroup "surfaceflinger" "" "cpuset"
    change_task_cgroup "system_server" "foreground" "cpuset"
    change_task_cgroup "netd|allocator" "foreground" "cpuset"
    change_task_cgroup "hardware.media.c2|vendor.mediatek.hardware" "background" "cpuset"
    change_task_cgroup "aal_sof|kfps|dsp_send_thread|vdec_ipi_recv|mtk_drm_disp_id|disp_feature|hif_thread|main_thread|rx_thread|ged_" "background" "cpuset"
    change_task_cgroup "pp_event|crtc_" "background" "cpuset"
}
unify_sched() {
    # clear stune & uclamp
    for d in /dev/stune/*/; do
        lock_val "0" $d/schedtune.boost
        lock_val "0" $d/schedtune.prefer_idle
    done
    for d in /dev/cpuctl/*/; do
        lock_val "0" $d/cpu.uclamp.min
        lock_val "0" $d/cpu.uclamp.latency_sensitive
    done
    for d in kernel walt; do
        mask_val "0" /proc/sys/$d/sched_force_lb_enable
    done
}
unify_devfreq() {
    for df in /sys/class/devfreq; do
        for d in $df/*cpubw $df/*gpubw $df/*llccbw $df/*cpu-cpu-llcc-bw $df/*cpu-llcc-ddr-bw $df/*cpu-llcc-lat $df/*llcc-ddr-lat $df/*cpu-ddr-latfloor $df/*cpu-l3-lat $df/*cdsp-l3-lat $df/*cdsp-l3-lat $df/*cpu-ddr-qoslat $df/*bpu-ddr-latfloor $df/*snoc_cnoc_keepalive; do
            lock_val "9999000000" "$d/max_freq"
        done
    done
    for d in DDR LLCC L3; do
        lock_val "9999000000" "/sys/devices/system/cpu/bus_dcvs/$d/*/max_freq"
    done
}
unify_lpm() {
    # Qualcomm enter C-state level 3 took ~500us
    lock_val "0" /sys/module/lpm_levels/parameters/lpm_ipi_prediction
    lock_val "0" /sys/module/lpm_levels/parameters/lpm_prediction
    lock_val "2" /sys/module/lpm_levels/parameters/bias_hyst
    for d in kernel walt; do
        mask_val "255" /proc/sys/$d/sched_busy_hysteresis_enable_cpus
        mask_val "2000000" /proc/sys/$d/sched_busy_hyst_ns
    done
}
disable_userspace_boost() {
    # xiaomi vip-task scheduler override
    chmod 0000 /dev/migt
    for f in /sys/module/migt/parameters/*; do
        chmod 0000 $f
    done
    # xiaomi perfservice
    stop vendor.perfservice
    stop miuibooster
    #stop vendor.miperf
    # brain service maybe not smart
    stop oneplus_brain_service 2>/dev/null
    # Qualcomm perfd
    stop perfd 2>/dev/null
    # Qualcomm&MTK perfhal
    perfhal_stop
    # libperfmgr
    stop vendor.power-hal-1-0
    stop vendor.power-hal-1-1
    stop vendor.power-hal-1-2
    stop vendor.power-hal-1-3
    stop vendor.power-hal-aidl
}
restart_userspace_boost() {
    # Qualcomm&MTK perfhal
    perfhal_start
    # libperfmgr
    start vendor.power-hal-1-0
    start vendor.power-hal-1-1
    start vendor.power-hal-1-2
    start vendor.power-hal-1-3
    start vendor.power-hal-aidl
}
disable_userspace_thermal() {
    killall mi_thermald
    # prohibit mi_thermald use cpu thermal interface
    for i in 0 2 4 6 7; do
        local maxfreq="$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq)"
        [ "$maxfreq" -gt "0" ] && lock_val "cpu$i $maxfreq" /sys/devices/virtual/thermal/thermal_message/cpu_limits
    done
}
restart_userspace_thermal() {
    killall mi_thermald
}
perfhal_stop() {
    for i in 0 1 2 3 4; do
        for j in 0 1 2 3 4; do
            stop "perf-hal-$i-$j" 2>/dev/null
        done
    done
    usleep 500
}
perfhal_start() {
    for i in 0 1 2 3 4; do
        for j in 0 1 2 3 4; do
            start "perf-hal-$i-$j" 2>/dev/null
        done
    done
}

ximi() {
  # set perms
  disable_kernel_boost
  disable_hotplug
  unify_sched
  unify_devfreq
  unify_lpm
  # reset memory
  disable_userspace_thermal
  restart_userspace_thermal
  disable_userspace_boost
  restart_userspace_boost
  # unify values
  disable_kernel_boost
  disable_hotplug
  unify_sched
  unify_devfreq
  unify_lpm

  stop vendor_tcpdump
  stop miuibooster
  stop mcd_service
  killall -9 mi_thermald

  BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
  if [ -d "$BUS_DIR" ]; then
    for d in $(ls $BUS_DIR); do
        [ ! -f $BUS_DIR/$d/hw_max_freq ] && continue
        MAX_FREQ=$(cat $BUS_DIR/$d/hw_max_freq)
        if [ -d "$BUS_DIR/$d" ]; then
          for df in $(ls $BUS_DIR/$d); do
              lock_val "$MAX_FREQ" "$BUS_DIR/$d/$df/max_freq"
          done
        fi
    done
  fi
  NUM_PWRLEVELS="/sys/class/kgsl/kgsl-3d0/num_pwrlevels"
  if [ -f "$NUM_PWRLEVELS" ]; then
    MIN_PWRLVL=$(($(cat "$NUM_PWRLEVELS") - 1))
    mask_val "$MIN_PWRLVL" /sys/class/kgsl/kgsl-3d0/default_pwrlevel
    mask_val "$MIN_PWRLVL" /sys/class/kgsl/kgsl-3d0/min_pwrlevel
  fi
  mask_val "0" /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel
  mask_val "0" /sys/class/kgsl/kgsl-3d0/bus_split
  mask_val "0" /sys/class/kgsl/kgsl-3d0/force_bus_on
  mask_val "0" /sys/class/kgsl/kgsl-3d0/force_clk_on
  mask_val "0" /sys/class/kgsl/kgsl-3d0/force_no_nap
  mask_val "0" /sys/class/kgsl/kgsl-3d0/force_rail_on
  mask_val "0" /sys/class/kgsl/kgsl-3d0/throttling
  mask_val "0" /proc/sys/walt/sched_boost
  mask_val "0" /sys/module/metis/parameters/cluaff_control
  mask_val "0" /sys/module/metis/parameters/mi_fboost_enable
  mask_val "0" /sys/module/metis/parameters/mi_freq_enable
  mask_val "0" /sys/module/metis/parameters/mi_link_enable
  mask_val "0" /sys/module/metis/parameters/mi_switch_enable
  mask_val "0" /sys/module/metis/parameters/mi_viptask
  mask_val "0" /sys/module/metis/parameters/mpc_fboost_enable
  mask_val "0" /sys/module/metis/parameters/vip_link_enable
  mask_val "0" /sys/module/perfmgr/parameters/perfmgr_enable

  migt=/sys/module/migt/parameters
  if [[ -e $migt ]]; then
    hide_value $migt/migt_freq '0:0 1:0 2:0 3:0 4:0 5:0 6:0 7:0'
    hide_value $migt/glk_freq_limit_start '0'
    hide_value $migt/glk_freq_limit_walt '0'
    hide_value $migt/glk_maxfreq '0 0 0'
    hide_value $migt/glk_minfreq '307200 633600 787200'
    hide_value $migt/migt_ceiling_freq '0 0 0'
    hide_value $migt/glk_disable '1'
    hide_value $migt/mi_freq_enable '0'
    hide_value $migt/force_stask_to_big '0'
    hide_value $migt/glk_fbreak_enable '0'
    hide_value $migt/force_reset_runtime '0'
    settings put secure speed_mode_enable 1
    chmod 000 $migt/*
    chmod 000 /sys/module/migt
    chmod 000 /sys/module/sched_walt/holders/migt/parameters
  fi
  glk=/proc/sys/glk
  if [[ -d $glk ]]; then
    hide_value $glk/glk_disable '1'
    hide_value $glk/freq_break_enable '0'
    hide_value $glk/game_minfreq_limit '0 0 0'
    hide_value $glk/game_maxfreq_limit '0 0 0'
    hide_value $glk/game_lowspeed_load '30 30 30'
    hide_value $glk/game_hispeed_load '80 80 80'
  fi
  migt=/proc/sys/migt
  if [[ -d $migt ]]; then
    hide_value $migt/force_stask_tob '0'
    hide_value $migt/enable_pkg_monitor '0'
    hide_value $migt/boost_pid '0'
  fi
  if [ -d "/sys/class/misc/migt" ]; then
    chmod 000 /sys/class/misc/migt
  fi
  if [ -d "/sys/module/sched_walt/holders/migt" ]; then
    chmod 000 /sys/module/sched_walt/holders/migt
  fi
}

#########

resetprop() {
  hide echo -n "resetprop: $@\n"
  hide resetprop "$@"
}
killall() {
  hide killall "$@"
}
chmod() {
  hide chmod "$@"
}
stop() {
  hide stop "$@"
}
start() {
  hide start "$@"
}

ptune() {

log "$(version)"
log "Running on $(platform) for $(device)"

# Allow vendor scheduler groups to fully utilize cores
lock $VS/util_threshold                    9999 #?
lock $VS/auto_uclamp_max                   1024 #130 130 512 512 512 512 512 670
lock $VS/auto_uclamp_max_st_util_threshold 9999 #0 or 700
lock $VS/auto_uclamp_max_st                1024 #1024 1024 1024 1024 1024 1024 1024 950
lock $VS/uclamp_max_filter_enable             0 #0=off, 1=on
lock $VS/auto_dvfs_headroom_enable            0 #0=off, 1=on
lock $VS/tapered_dvfs_headroom_enable         0 #0=off, 1=on
lock $VS/dvfs_headroom                     1280 #1100

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
schedgroup bg        0    1024 0 1 0 #0     512
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
cpuf="$(cat $CS/cpus)"
cpuset background                   "$cpuf" #0-3
cpuset camera-daemon                "$cpuf" #0-7
cpuset camera-daemon-high-group     "$cpuf" #6-7
cpuset camera-daemon-mid-group      "$cpuf" #4-5
cpuset camera-daemon-mid-high-group "$cpuf" #4-7
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
## 120Hz
#zsched 1 0 8333333 8 #2 1 8000000 (10/14)
## 240Hz
#sched 1 0 4166666 4
## 1000Hz
#sched 1 0 1000000 1
## 2000Hz
#sched 1 0 500000 1
## 4000Hz
#sched 1 0 250000 1
## 5000Hz
sched 1 0 200000 1
## 8000Hz
#sched 1 0 125000 1
## 10000Hz
#sched 1 0 100000 1
## No limit
#sched 1 0 0 1

# Speed up disk access
# scheduler
# number of requests
# async depth
blocksched mq-deadline 500 20000 #mq-deadline 62 62

# Adjust our kernel's tunables
lock $VM/dirty_writeback_centisecs 0
lock $VM/sched_child_runs_first    1
lock $VM/swappiness                0
lock $VM/vfs_cache_pressure        1
lock $THP/shmem_enabled            within_size
lock $THP/defrag                   always
lock $THP/enabled                  always

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
#resetprop -n debug.sf.region_sampling_duration_ns      4166666  #unset
resetprop -n debug.sf.region_sampling_period_ns        99999984 #unset
resetprop -n debug.sf.region_sampling_timer_timeout_ns 99999984 #unset

# Disable limiting the maximum frame rate for games at 60Hz
resetprop -n debug.graphics.game_default_frame_rate.disabled true #unset

if [ "$(platform)" = "laguna" ]; then
  # Raise the amount of SurfaceFlinger buffers that should remain allocated to prevent GC overhead
  resetprop -n ro.surface_flinger.max_frame_buffer_acquired_buffers 7 #3

  # PowerVR GPU scheduling rate in milliseconds
  ## 50Hz (stock)
  #powervr_sched 20
  ## ~120Hz
  #powervr_sched 8
  ## ~240Hz
  #powervr_sched 4
  ## 1000Hz
  powervr_sched 1
#elif [ "$(platform)" = "gs101" ] || \
#     [ "$(platform)" = "gs201" ] || \
#     [ "$(platform)" = "zuma" ]  || \
#     [ "$(platform)" = "zumapro" ]; then
  # Mali GPU scheduling rate in milliseconds
  ## 50Hz (stock)
  #mali_sched 20
  ## ~120Hz
  #mali_sched 8
  ## ~240Hz
  #mali_sched 4
  ## 1000Hz
  #mali_sched 1
fi

# Xiaomi-oriented support amongst other potential Qualcomm devices
ximi

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
if [ "$(brand)" == "google" ]; then
  zram
fi

# Avoid waiting to finalize values if we're already through init's boot sequence
if [ "$(bootcomplete)" -eq "1" ]; then
  log "No need to finalize new values"
  return || exit 0
fi

# Restart services to take in the new values
restart() {
  log "Stopping $1"
  stop $2
  log "Starting $1"
  start $2
}
restart "SurfaceFlinger" surfaceflinger
restart "libperfmgr"     vendor.power-hal-aidl

log "Waiting for boot complete"
while [ "$(bootcomplete)" != "1" ]; do sleep 1; done

log "Finalizing values"
ptune

log "Pixel Tune is done!"
