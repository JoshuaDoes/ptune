#!/system/bin/sh

name() {
  echo "Pixel Tune"
}
version() {
  echo "v2.0.0-alpha13"
}
build() {
  echo "$(name) $(version)"
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
soc() {
  getprop ro.soc.model
}
tz() {
  getprop persist.sys.timezone
}

## CONFIG

BOOT_WAIT=5

##

## RUNTIME

#MODDIR=${0%/*}
DIRSH="$(dirname $0)"
DIRBIN="$DIRSH/bin"
export PATH="$DIRBIN:$PATH"

cd "$DIRSH"

TMPC=/cache/ptune
STOP=$TMPC/stop_powerpulse
LOGFILE=$TMPC/service.log

VM=/proc/sys/vm
KR=/proc/sys/kernel
CS=/dev/cpuset
VS=/proc/vendor_sched
VSM=$VS/min_granularity_ns
VSL=$VS/latency_ns
VSG=$VS/groups
FREQ=/sys/devices/system/cpu/cpufreq
DF=/sys/class/devfreq
MM=/sys/kernel/mm
THP=$MM/transparent_hugepage

BIGMAX=9999999999

##

logwipe() {
  rm -f $LOGFILE
  mkdir -p $(dirname $LOGFILE)
}

log() {
  ls="[$(date)] $1"
  echo "$ls" >> "$LOGFILE"
  echo "$ls"
}

hide() {
#  if command "$@" >>"$LOGFILE" 2>&1; then
#    log "[#] $*"
#  else
#    log "[!] $*"
#  fi
  if ! command "$@" >>"$LOGFILE" 2>&1; then
    log "[!] $*"
  fi
}

lock() {
  if [ $# -lt 1 ]; then return; fi
  if [ ! -f "$1" ]; then return; fi
  chown root:root "$1"
  if [ $# -gt 1 ]; then
    chmod 200 "$1" #write
    log "[*] $2 > $1"
    echo "$2" > "$1"
  else
    log "[*] $1"
  fi
  chmod 000 "$1" #lock
}
lockread() {
  if [ $# -lt 1 ]; then return; fi
  if [ ! -f "$1" ] && [ ! -c "$1" ]; then return; fi
  chmod 400 "$1" #read
  cat "$1"
  chmod 000 "$1" #lock
}

compare() {
  if echo "$1" | grep "$2" - >/dev/null; then
    true
  else
    false
  fi
  return $?
}

powervr_sched() {
  gpu="/sys/class/devfreq/34f00000.gpu0"
  poll="$gpu/polling_interval"
  mif="$gpu/min_freq"
  maf="$gpu/max_freq"
  tf="$gpu/target_freq"
  vm="$gpu/vote_manager"

  lock "$poll" $1

  min=${2:-0}
  max=${3:-$BIGMAX}

  lock "$mif" $min
  lock "$maf" $max
  lock "$tf" $min
  lock "$vm/soft_min_freq" $min
  lock "$vm/soft_max_freq" $max
}

mali_sched() {
  gpu="/sys/devices/platform/1c500000.mali"
  dvfs="$gpu/dvfs_period"
  mif="$gpu/min_freq"
  maf="$gpu/max_freq"
  hmif="$gpu/hint_min_freq"
  hmaf="$gpu/hint_max_freq"
  smif="$gpu/scaling_min_freq"
  smicf="$gpu/scaling_min_compute_freq"
  smaf="$gpu/scaling_max_freq"

  lock "$dvfs" $1

  min=${2:-0}
  max=${3:-$BIGMAX}

  lock "$mif" $min
  lock "$maf" $max
  lock "$hmif" $min
  lock "$hmaf" $max
  lock "$smif" $min
  lock "$smicf" $min
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
      lock "$vm/soft_min_freq" $(lockread "$policy/cpuinfo_min_freq")
      lock "$vm/soft_max_freq" $(lockread "$policy/cpuinfo_max_freq")
    fi
  done
}

cpuset() {
  cs="$CS/$1"
  if [ -d "$cs" ]; then
    echo "$2" > "$cs/cpus"
    log "$1: $2"
  fi
}

devfreq() {
  if [ -d "$DF" ]; then
    log "Unlocking all devfreq ranges"
    cd "$DF"
    for d in *; do
      if [ ! -d "$d" ]; then continue; fi
      log "Poking devfreq: $d"

      #Don't touch the frequency range for blacklisted nodes
      case $d in
        dpu_freq) : ;;
        *)
          log "Unlocking devfreq: $d"

          nmin="$d/min_freq"
          nmax="$d/max_freq"
          ntgt="$d/target_freq"
          ngov="$d/governor"

          min=$(lockread "$nmin")
          max=$(lockread "$nmax")
          tgt=$(lockread "$ntgt")
          gov=$(lockread "$ngov")
          log "Old: ${min:-0}Hz-${max:-0}Hz: targeting ${tgt:-0}Hz on $gov"

          #Unlock the frequency range
          lock "$nmin" 0
          lock "$nmax" $BIGMAX
          lock "$ntgt" $BIGMAX

          #Tensor is weird bro
          lock "$ngov" powersave

          min=$(lockread "$nmin")
          max=$(lockread "$nmax")
          tgt=$(lockread "$ntgt")
          gov=$(lockread "$ngov")
          log "New: ${min:-0}Hz-${max:-0}Hz: targeting ${tgt:-0}Hz on $gov"

          vm="$d/vote_manager"
          if [ -d "$vm" ]; then
            nvmdmin="$vm/debug_min_freq"
            nvmdmax="$vm/debug_max_freq"
            nvmpmin="$vm/powerhint_min_freq"
            nvmpmax="$vm/powerhint_max_freq"
            nvmsmin="$vm/soft_min_freq"
            nvmsmax="$vm/soft_max_freq"
            nvmtmax="$vm/thermal_max_freq"

            vmdmin=$(lockread "$nvmdmin")
            vmdmax=$(lockread "$nvmdmax")
            vmpmin=$(lockread "$nvmpmin")
            vmpmax=$(lockread "$nvmpmax")
            vmsmin=$(lockread "$nvmsmin")
            vmsmax=$(lockread "$nvmsmax")
            vmtmax=$(lockread "$nvmtmax")
            val="$vmdmin/$vmdmax/$vmpmin/$vmpmax/$vmsmin/$vmsmax/$vmtmax"
            log "Old (debug/powerhint/soft) min/max, thermal max: $val"

            lock "$nvmdmin" 0
            lock "$nvmpmin" 0
            lock "$nvmsmin" 0
            lock "$nvmdmax" $max
            lock "$nvmpmax" $max
            lock "$nvmsmax" $max
            lock "$nvmtmax" $max

            vmdmin=$(lockread "$nvmdmin")
            vmdmax=$(lockread "$nvmdmax")
            vmpmin=$(lockread "$nvmpmin")
            vmpmax=$(lockread "$nvmpmax")
            vmsmin=$(lockread "$nvmsmin")
            vmsmax=$(lockread "$nvmsmax")
            vmtmax=$(lockread "$nvmtmax")
            val="$vmdmin/$vmdmax/$vmpmin/$vmpmax/$vmsmin/$vmsmax/$vmtmax"
            log "New (debug/powerhint/soft) min/max, thermal max: $val"
          fi
          ;;
      esac

      #Force the Emerald Hill memory compressor to run full speed
      if [ "$d" = "eh_freq" ]; then lock "$d/governor" performance; fi
    done
    cd -
  fi
}

ioprio() {
  for pid_dir in /proc/[0-9]*; do
    # Extract the PID from the directory path
    pid="${pid_dir#/proc/}"

    # Apply ionice (Class 1 = Real-time, Priority 4)
    # Redirect all output to /dev/null for total silence
    ionice -c 1 -n 4 -p "$pid" >/dev/null 2>&1
  done
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
  if [ -e "$1" ]; then
    umount "$1" 2>/dev/null
    c_path="/cache${1}"
    if [ ! -f "$c_path" ]; then
      mkdir -p "$c_path"
      rm -r "$c_path"
    fi
    chattr -i "$c_path"
    cp -f "$1" "$c_path"
    if [ "$2" != "" ]; then
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
        lock_val "0" "$d"schedtune.boost
        lock_val "0" "$d"schedtune.prefer_idle
    done
    for d in /dev/cpuctl/*/; do
        lock_val "0" "$d"cpu.uclamp.min
        lock_val "0" "$d"cpu.uclamp.latency_sensitive
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
        local maxfreq="$(lockread /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq)"
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
        MAX_FREQ=$(lockread $BUS_DIR/$d/hw_max_freq)
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
  if [ -e $migt ]; then
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
  if [ -d $glk ]; then
    hide_value $glk/glk_disable '1'
    hide_value $glk/freq_break_enable '0'
    hide_value $glk/game_minfreq_limit '0 0 0'
    hide_value $glk/game_maxfreq_limit '0 0 0'
    hide_value $glk/game_lowspeed_load '30 30 30'
    hide_value $glk/game_hispeed_load '80 80 80'
  fi
  migt=/proc/sys/migt
  if [ -d $migt ]; then
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
  hide resetprop -n "$@" #Enforce bypassing property_service with all prop calls!
}
killall() {
  hide killall "$@"
}
cd() {
  hide cd "$@"
}
stop() {
  hide stop "$@"
}
start() {
  hide start "$@"
}
ionice() {
  hide ionice "$@"
}

ptune() {

log "$(build)"
log "Running on $(platform) for $(device)"
log "Workdir: $DIRSH"

#### Allow vendor scheduler groups to fully utilize cores
###lock $VS/util_threshold                    9999 #?
###lock $VS/auto_uclamp_max                   1024 #130 130 512 512 512 512 512 670
###lock $VS/auto_uclamp_max_st_util_threshold 9999 #0 or 700
###lock $VS/auto_uclamp_max_st                1024 #1024 1024 1024 1024 1024 1024 1024 950
###lock $VS/uclamp_max_filter_enable             0 #0=off, 1=on
###lock $VS/auto_dvfs_headroom_enable            0 #0=off, 1=on
###lock $VS/tapered_dvfs_headroom_enable         0 #0=off, 1=on
###lock $VS/dvfs_headroom                     1280 #1100
###
##### uclamp max ##
#### LITTLE = 158
####    MID = 490
####    BIG = 1024
###################
#### group
#### uclamp min
#### uclamp max
#### prefer big
#### prefer idle
#### task spread
###schedgroup bg        0    1024 0 1 0 #0     512
###schedgroup cam       0    1024 0 1 0 #1    1024
###schedgroup cam_power 0    1024 0 1 0 #0    1024
###schedgroup dex2oat   0    1024 0 1 0 #0     615
###schedgroup fg        0    1024 0 1 0 #0    1024
###schedgroup fg_wi     0    1024 0 1 0 #0    1024
###schedgroup nnapi     0    1024 0 1 0 #225  1024
###schedgroup ota       0    1024 0 1 0 #0     512
###schedgroup rt        0    1024 0 1 0 #0    1024
###schedgroup sf        0    1024 0 1 0 #0    1024
###schedgroup sys       0    1024 0 1 0 #0    1024
###schedgroup sys_bg    0    1024 0 1 0 #0     512
###schedgroup ta        0    1024 0 1 0 #1    1024
###
#### cpuset | cpus
###cpuf="$(cat $CS/cpus)"
###cpuset background                   $cpuf #0-3
###cpuset camera-daemon                $cpuf #0-7
###cpuset camera-daemon-high-group     $cpuf #6-7
###cpuset camera-daemon-mid-group      $cpuf #4-5
###cpuset camera-daemon-mid-high-group $cpuf #4-7
###cpuset foreground                   $cpuf #0-5
###cpuset foreground_window            $cpuf #0-5
###cpuset restricted                   0-1   #0-3
###cpuset system                       $cpuf #0-7 (custom, !sys)
###cpuset system-background            $cpuf #0-3
###cpuset top-app                      $cpuf #0-7
###
#### Give our CPU a lunch break when it wants one
#### down delay | up delay
###delayfreqs 0 0 #5000 0
###
#### Pixel CPUFreq scheduler rate
#### adpf rampup multiplier (default 2)
#### reduce prefer idle (default 1)
#### latency in nanoseconds (default 8000000)
#### latency in milliseconds, combo of cpu_busy_limit_ms (default 10) and response_time_ms (default 14)
##### 120Hz
####sched 1 0 8333333 8
##### 240Hz
####sched 1 0 4166666 4
##### 500Hz
####sched 1 0 2000000 2
##### 1KHz
####sched 1 0 1000000 1
##### 2KHz
####sched 1 0 500000 1
##### 4KHz
####sched 1 0 250000 1
##### 5KHz
####sched 1 0 200000 1
##### ~6.0240001KHz
####sched 1 0 166666 1
##### 8KHz
####sched 1 0 125000 1
##### 10KHz
####sched 1 0 100000 1
##### 15KHz
####sched 1 0 75000 1
##### 20KHz
####sched 1 0 50000 1
##### 30KHz
####sched 1 0 33333 1
##### 40KHz
####sched 1 0 25000 1
##### 50KHz
####sched 1 0 20000 1
##### ~88.5KHz
####sched 1 0 11300 1
##### ~120KHz
####sched 1 0 8333 1
##### ~177KHz
####sched 1 0 5650 1
##### 2MHz
###sched 1 0 500 1
##### No limit
####sched 1 0 0 1
###
#### Speed up disk access
#### scheduler
#### number of requests
#### async depth
###blocksched mq-deadline 500 5000 #mq-deadline 62 62
###
#### Adjust our kernel's tunables
###lock $VM/dirty_writeback_centisecs 0
###lock $VM/sched_child_runs_first    0
###lock $VM/swappiness                1
###lock $VM/vfs_cache_pressure        1
###lock $THP/shmem_enabled            within_size
###lock $THP/defrag                   always
###lock $THP/enabled                  always

# Set the ADPF timer to 240Hz (stock 60Hz)
resetprop vendor.powerhal.adpf.rate 4166666 #16666666

# Allow swap to reach 99% before triggering LMKD
resetprop ro.lmk.swap_free_low_percentage 1

# Disable limiting the maximum frame rate for games at 60Hz
resetprop debug.graphics.game_default_frame_rate.disabled true #unset

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
resetprop debug.sf.region_sampling_duration_ns      8333333  #unset
resetprop debug.sf.region_sampling_period_ns        99999984 #unset
resetprop debug.sf.region_sampling_timer_timeout_ns 99999984 #unset

# Instruct the Render Engine to use EGL_IMG_context_priority hint if available
resetprop ro.surface_flinger.use_context_priority true

# Some hardware can do RGB->YUV conversion more efficiently in hardware
# controlled by HWC than in hardware controlled by the video encoder.
# This instruct VirtualDisplaySurface to use HWC for such conversion on
# GL composition.
resetprop ro.surface_flinger.force_hwc_copy_for_virtual_displays true #unset

# Indicates if Sync framework is available. Sync framework provides fence
# mechanism which significantly reduces buffer processing latency.
resetprop ro.surface_flinger.running_without_sync_framework false

# When enabled, SurfaceFlinger will attempt to clear the per-layer HAL buffer cache slots for
# buffers when they are evicted from the app cache by using additional setLayerBuffer commands.
# Ideally, this behavior would always be enabled to reduce graphics memory consumption. However,
# Some HAL implementations may not support the additional setLayerBuffer commands used to clear
# the cache slots.
resetprop ro.surface_flinger.clear_slots_with_set_layer_buffer true #unset

# setDisplayPowerTimerMs indicates what is considered a timeout in milliseconds for Scheduler.
# This value is used by the Scheduler to trigger display power inactivity callbacks that will
# keep the display in peak refresh rate as long as display power is not in normal mode.
# Setting this property to 0 means there is no timer.
resetprop ro.surface_flinger.set_display_power_timer_ms 1 #unset

# Sets the timeout used to rate limit DISPLAY_UPDATE_IMMINENT Power HAL notifications.
# SurfaceFlinger wakeups will trigger this boost whenever they are separated by more than this
# duration (specified in milliseconds). A value of 0 disables the rate limit, and will result in
# Power HAL notifications every time SF wakes up.
resetprop ro.surface_flinger.display_update_imminent_timeout_ms 1 #50

# setTouchTimerMs indicates what is considered a timeout in milliseconds for Scheduler.
# This value is used by the Scheduler to trigger touch inactivity callbacks that will switch the
# display to a lower refresh rate. Setting this property to 0 means there is no timer.
resetprop ro.surface_flinger.set_touch_timer_ms 4 #200

# Indicates whether Scheduler's idle timer should support a display driver timeout in the kernel.
# The value of set_idle_timer_ms should be shorter in time than the timeout duration in the kernel.
resetprop ro.surface_flinger.support_kernel_idle_timer true #unset

# Similar to set_touch_timer_ms, but determines how long to wait before processing any new events.
resetprop ro.surface_flinger.set_idle_timer_ms 4 #80

#### PowerVR GPU scheduling rate in milliseconds
##### Max freq, make the scheduler wait 10 seconds
###powervr_sched 10000 $BIGMAX $BIGMAX
##### 50Hz (stock)
####powervr_sched 20
##### ~120Hz
####powervr_sched 8
##### ~240Hz
####powervr_sched 4
##### 500Hz
####powervr_sched 2
##### 1KHz
####powervr_sched 1
##### No limit
####powervr_sched 0
###
#### Mali GPU scheduling rate in milliseconds
##### Max freq, make the scheduler wait 1 second
###mali_sched 10000 $BIGMAX $BIGMAX
##### 50Hz (stock)
####mali_sched 20
##### ~120Hz
####mali_sched 8
##### ~240Hz
####mali_sched 4
##### 500Hz
####mali_sched 2
##### 1KHz
####mali_sched 1
##### No limit
####mali_sched 0

if [ "$(platform)" = "laguna" ]; then
  log "Target: Tensor G5 (laguna)"

  # laguna has 7 total HWC layers
  resetprop ro.surface_flinger.max_frame_buffer_acquired_buffers 7 #3
elif [ "$(platform)" = "zuma" ] || \
     [ "$(platform)" = "zumapro" ]; then
  log "Target: Tensor G3 (zuma) | G4 (zumapro)"

  # zuma/zumapro can at least handle 6 total HWC layers (TODO: confirm count)
  resetprop ro.surface_flinger.max_frame_buffer_acquired_buffers 6 #3
elif [ "$(platform)" = "gs101" ] || \
     [ "$(platform)" = "gs201" ]; then
  log "Target: Tensor G1 (gs101) | G2 (gs201)"

  # gs101/gs201 has 6 total HWC layers
  resetprop ro.surface_flinger.max_frame_buffer_acquired_buffers 6 #3

###  ## CPU: 240Hz (stock: 125Hz)
###  sched 1 0 4166666 4
###
###  ## GPU: 50Hz (stock: 50Hz)
###  mali_sched 20
fi

if [ "$(brand)" = "google" ]; then
  # Controls the default frame rate override of game applications. Ideally, game applications set
  # desired frame rate via setFrameRate() API. However, to cover the scenario when the game didn't
  # have a set frame rate, we introduce the default frame rate. The priority of this override is the
  # lowest among setFrameRate() and game intervention override.
  if [ "$(device)" = "bluejay" ]; then
    resetprop ro.surface_flinger.game_default_frame_rate_override 60
  elif [ "$(device)" = "oriole" ] || \
       [ "$(device)" = "cheetah" ] || \
       [ "$(device)" = "lynx" ] || \
       [ "$(device)" = "akita" ]; then
    resetprop ro.surface_flinger.game_default_frame_rate_override 90
  else
    resetprop ro.surface_flinger.game_default_frame_rate_override 120
  fi
fi

# Xiaomi-oriented support (targeting `sheng`) amongst other potential Qualcomm devices
###if [ "$(brand)" != "google" ]; then
###  ximi
###fi

}

zram() {
  local gigs=${1:-1}
  local comp=${2:-zstd}

  log "$(zramcfg)"

  local kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  local zramB=$(awk -v kb="$kb" -v g="$gigs" 'BEGIN{printf "%.0f\n", kb*1024 - g*1073741824}')
  local sizeTxt=$(awk -v kb="$kb" 'BEGIN{print int(kb/1048576)+1}')
  local zramTxt=$(awk -v b="$zramB" 'BEGIN{print int(b/1073741824)+1}')

  log "Resizing ZRAM to ${zramTxt}/${sizeTxt}GB"
  log "$(zramcfg -s $zramB -c $comp -e)"
}

vrestart() {
  vstop "$1" $2 && vstart "$1" $2
}
restart() {
  stop "$1" && start "$1"
}
vstop() {
  log "Stopping $1"
  stop $2
}
vstart() {
  log "Starting $1"
  start $2
}
wait() {
  if [ -f "$STOP" ]; then
    log "Waiting"
    while true; do
      sleep 5
      if [ ! -f "$STOP" ]; then break; fi
    done
  fi
}

#########

logwipe

log "Setting initial prop values"
ptune

# Restart services to take in our new values
stop bootanim
restart surfaceflinger
restart vendor.power-hal-aidl #To accept our powerhint.json
start bootanim

while true; do
  killall powerpulse
  log "Starting powerpulse..."
  powerpulse "$DIRSH" "$(brand)" "$(platform)" "$(device)" "$(soc)" "$(tz)"
  log "Lost powerpulse: exit status $?"
  wait
done

###if [ -f "$DIRSH/debug" ]; then
###  # Remove the debug file to prevent overwriting the logcat on next boot
###  rm -f "$DIRSH/debug"
###
###  # Start logcat in case of early init failure
###  rm -f /cache/logcat.log
###  logcat > /cache/logcat.log &
###fi
###
###logwipe
###
###vrestart() {
###  vstop "$1" $2 && vstart "$1" $2
###}
###vstop() {
###  log "Stopping $1"
###  stop $2
###}
###vstart() {
###  log "Starting $1"
###  start $2
###}
###
###if [ "$(bootcomplete)" -eq "0" ]; then
###  vstop "boot animation" bootanim
###  vstop "SurfaceFlinger" surfaceflinger
###fi
###
###log "Setting initial boot values"
###ptune
###
###if [ "$(brand)" = "google" ] && compare "$(soc)" "Tensor"; then
###    #Take advantage of lz77eh for all of RAM
###    lock $VM/swappiness 100
###    zram 0 lz77eh
###fi
###
#### Avoid waiting to finalize values if we're already through init's boot sequence
###if [ "$(bootcomplete)" -eq "1" ]; then
###  log "No need to finalize new values"
###  return || exit 0
###fi
###
#### Restart services to take in the new values
###vrestart "libperfmgr (power HAL)" vendor.power-hal-aidl
###vrestart "SurfaceFlinger"         surfaceflinger
###vstart   "boot animation"         bootanim
###
###log "Waiting for boot complete"
###while [ "$(bootcomplete)" -eq "0" ]; do sleep 1; done
###
###log "Waiting ${BOOT_WAIT}s to let init finish"
###sleep $BOOT_WAIT
###
####Unlock safe devfreq ranges
###devfreq
###
####Make everything alive run a commune
###ioprio
###
###log "Finalizing values"
###ptune
###
###log "Pixel Tune is done!"
###
##### Consider not using $BOOT_WAIT?
###VS_NS=""
###if [ -f $VSM ]; then
###  VS_NS=$VSM
###elif [ -f $VSL ]; then
###  VS_NS=$VSL
###fi
###if [ "$VS_NS" != "" ]; then
###  VS_NSV=$(cat $VS_NS)
###  log "Watching $VS_NS for changes: $VS_NSV"
###  while true; do
###    sleep $BOOT_WAIT
###    if [ "$(cat $VS_NS)" != "$VS_NSV" ]; then
###      log "Mismatched VS_NS"
###      ptune
###      sleep $BOOT_WAIT
###    fi
###  done
###fi
