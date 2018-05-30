function __print_additional_functions() {
cat <<EOF
Additional functions:
- cout:            Changes directory to out.
- mmp:             Builds all of the modules in the current directory and pushes them to the device.
- mmap:            Builds all of the modules in the current directory and its dependencies, then pushes the package to the device.
- mmmp:            Builds all of the modules in the supplied directories and pushes them to the device.
- mms:             Short circuit builder. Quickly re-build the kernel, rootfs, boot and system images
                   without deep dependencies. Requires the full build to have run before.
- mkap:            Builds the module(s) using mka and pushes them to the device.
- repodiff:        Diff 2 different branches or tags within the same repo
- repolastsync:    Prints date and time of last repo sync.
- reposync:        Parallel repo sync using ionice and SCHED_BATCH.
- installboot:     Installs a boot.img to the connected device.
- installrecovery: Installs a recovery.img to the connected device.
EOF
}

function brunch()
{
    breakfast $1
    xospapps_essentials
    if [ $2 ]; then
    	make xosp $2
    else
    	local NUM_CPUS=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
    	make xosp -j$NUM_CPUS
    fi
    return $?
}

function breakfast()
{
    target=$1
    local variant=$2
    XOSP_DEVICES_ONLY="true"
    unset LUNCH_MENU_CHOICES
    add_lunch_combo full-eng
    for f in `/bin/ls vendor/xosp/vendorsetup.sh 2> /dev/null`
        do
            echo "including $f"
            . $f
        done
    unset f

    if [ $# -eq 0 ]; then
        # No arguments, so let's have the full menu
        lunch
    else
        echo "z$target" | grep -q "-"
        if [ $? -eq 0 ]; then
            # A buildtype was specified, assume a full device name
            lunch $target
        else
            # This is probably just the XOSP model name
            if [ -z "$variant" ]; then
                variant="userdebug"
            fi
            lunch xosp_$target-$variant
        fi
    fi
    return $?
}

alias bib=breakfast

function eat()
{
    if [ "$OUT" ] ; then
        MODVERSION=$(get_build_var XOSP_VERSION)
        ZIPFILE=$MODVERSION.zip
        ZIPPATH=$OUT/$ZIPFILE
        if [ ! -f $ZIPPATH ] ; then
            echo "Nothing to eat"
            return 1
        fi
        adb start-server # Prevent unexpected starting server message from adb get-state in the next line
        if [ $(adb get-state) != device -a $(adb shell test -e /sbin/recovery 2> /dev/null; echo $?) != 0 ] ; then
            echo "No device is online. Waiting for one..."
            echo "Please connect USB and/or enable USB debugging"
            until [ $(adb get-state) = device -o $(adb shell test -e /sbin/recovery 2> /dev/null; echo $?) = 0 ];do
                sleep 1
            done
            echo "Device Found.."
        fi
        if (adb shell getprop ro.xosp.device | grep -q "$XOSP_BUILD"); then
            # if adbd isn't root we can't write to /cache/recovery/
            adb root
            sleep 1
            adb wait-for-device
            cat << EOF > /tmp/command
--sideload_auto_reboot
EOF
            if adb push /tmp/command /cache/recovery/ ; then
                echo "Rebooting into recovery for sideload installation"
                adb reboot recovery
                adb wait-for-sideload
                adb sideload $ZIPPATH
            fi
            rm /tmp/command
        else
            echo "The connected device does not appear to be $XOSP_BUILD, run away!"
        fi
        return $?
    else
        echo "Nothing to eat"
        return 1
    fi
}

function omnom()
{
    brunch $*
    eat
}

function cout()
{
    if [  "$OUT" ]; then
        cd $OUT
    else
        echo "Couldn't locate out directory.  Try setting OUT."
    fi
}

function dddclient()
{
   local OUT_ROOT=$(get_abs_build_var PRODUCT_OUT)
   local OUT_SYMBOLS=$(get_abs_build_var TARGET_OUT_UNSTRIPPED)
   local OUT_SO_SYMBOLS=$(get_abs_build_var TARGET_OUT_SHARED_LIBRARIES_UNSTRIPPED)
   local OUT_VENDOR_SO_SYMBOLS=$(get_abs_build_var TARGET_OUT_VENDOR_SHARED_LIBRARIES_UNSTRIPPED)
   local OUT_EXE_SYMBOLS=$(get_symbols_directory)
   local PREBUILTS=$(get_abs_build_var ANDROID_PREBUILTS)
   local ARCH=$(get_build_var TARGET_ARCH)
   local GDB
   case "$ARCH" in
       arm) GDB=arm-linux-androideabi-gdb;;
       arm64) GDB=arm-linux-androideabi-gdb; GDB64=aarch64-linux-android-gdb;;
       mips|mips64) GDB=mips64el-linux-android-gdb;;
       x86) GDB=x86_64-linux-android-gdb;;
       x86_64) GDB=x86_64-linux-android-gdb;;
       *) echo "Unknown arch $ARCH"; return 1;;
   esac

   if [ "$OUT_ROOT" -a "$PREBUILTS" ]; then
       local EXE="$1"
       if [ "$EXE" ] ; then
           EXE=$1
           if [[ $EXE =~ ^[^/].* ]] ; then
               EXE="system/bin/"$EXE
           fi
       else
           EXE="app_process"
       fi

       local PORT="$2"
       if [ "$PORT" ] ; then
           PORT=$2
       else
           PORT=":5039"
       fi

       local PID="$3"
       if [ "$PID" ] ; then
           if [[ ! "$PID" =~ ^[0-9]+$ ]] ; then
               PID=`pid $3`
               if [[ ! "$PID" =~ ^[0-9]+$ ]] ; then
                   # that likely didn't work because of returning multiple processes
                   # try again, filtering by root processes (don't contain colon)
                   PID=`adb shell ps | \grep $3 | \grep -v ":" | awk '{print $2}'`
                   if [[ ! "$PID" =~ ^[0-9]+$ ]]
                   then
                       echo "Couldn't resolve '$3' to single PID"
                       return 1
                   else
                       echo ""
                       echo "WARNING: multiple processes matching '$3' observed, using root process"
                       echo ""
                   fi
               fi
           fi
           adb forward "tcp$PORT" "tcp$PORT"
           local USE64BIT="$(is64bit $PID)"
           adb shell gdbserver$USE64BIT $PORT --attach $PID &
           sleep 2
       else
               echo ""
               echo "If you haven't done so already, do this first on the device:"
               echo "    gdbserver $PORT /system/bin/$EXE"
                   echo " or"
               echo "    gdbserver $PORT --attach <PID>"
               echo ""
       fi

       OUT_SO_SYMBOLS=$OUT_SO_SYMBOLS$USE64BIT
       OUT_VENDOR_SO_SYMBOLS=$OUT_VENDOR_SO_SYMBOLS$USE64BIT

       echo >|"$OUT_ROOT/gdbclient.cmds" "set solib-absolute-prefix $OUT_SYMBOLS"
       echo >>"$OUT_ROOT/gdbclient.cmds" "set solib-search-path $OUT_SO_SYMBOLS:$OUT_SO_SYMBOLS/hw:$OUT_SO_SYMBOLS/ssl/engines:$OUT_SO_SYMBOLS/drm:$OUT_SO_SYMBOLS/egl:$OUT_SO_SYMBOLS/soundfx:$OUT_VENDOR_SO_SYMBOLS:$OUT_VENDOR_SO_SYMBOLS/hw:$OUT_VENDOR_SO_SYMBOLS/egl"
       echo >>"$OUT_ROOT/gdbclient.cmds" "source $ANDROID_BUILD_TOP/development/scripts/gdb/dalvik.gdb"
       echo >>"$OUT_ROOT/gdbclient.cmds" "target remote $PORT"
       # Enable special debugging for ART processes.
       if [[ $EXE =~ (^|/)(app_process|dalvikvm)(|32|64)$ ]]; then
          echo >> "$OUT_ROOT/gdbclient.cmds" "art-on"
       fi
       echo >>"$OUT_ROOT/gdbclient.cmds" ""

       local WHICH_GDB=
       # 64-bit exe found
       if [ "$USE64BIT" != "" ] ; then
           WHICH_GDB=$ANDROID_TOOLCHAIN/$GDB64
       # 32-bit exe / 32-bit platform
       elif [ "$(get_build_var TARGET_2ND_ARCH)" = "" ]; then
           WHICH_GDB=$ANDROID_TOOLCHAIN/$GDB
       # 32-bit exe / 64-bit platform
       else
           WHICH_GDB=$ANDROID_TOOLCHAIN_2ND_ARCH/$GDB
       fi

       ddd --debugger $WHICH_GDB -x "$OUT_ROOT/gdbclient.cmds" "$OUT_EXE_SYMBOLS/$EXE"
  else
       echo "Unable to determine build system output dir."
   fi
}

function xospapps_essentials() {
    xospappsessentials="https://xospapps.xosp.org"
    function xospapps_essentials_done {
        echo -e "Done."
    }
    function xospapps_essentials_dwnlderror {
        echo -e "Couldn't download, please check your connection."
        exit 0
    }
    if wget -q -t 10 -T 20 --spider http://xosp.org
        then
            echo -e "Environment connected to internet!"
            echo -e "Downloading the essentials XOSPApps for the compilation..."
            mkdir -p essentials_xosp_apps/essentials;
            cd essentials_xosp_apps
            echo -e "Downloading Xperia Home..."
            xospapps_essentials_Home="essentials/Home/Home.apk"
            if [[ $(md5sum ${xospapps_essentials_Home} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_Home}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_Home}
                    mkdir essentials/Home
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_Home} -O ${xospapps_essentials_Home} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading SemCalendar..."
            xospapps_essentials_SemCalendar="essentials/SemCalendar/SemCalendar.apk"
            if [[ $(md5sum ${xospapps_essentials_SemCalendar} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_SemCalendar}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_SemCalendar}
                    mkdir essentials/SemCalendar
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_SemCalendar} -O ${xospapps_essentials_SemCalendar} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading SemcClock..."
            xospapps_essentials_SemcClock="essentials/SemcClock/SemcClock.apk"
            if [[ $(md5sum ${xospapps_essentials_SemcClock} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_SemcClock}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_SemcClock}
                    mkdir essentials/SemcClock
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_SemcClock} -O ${xospapps_essentials_SemcClock} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading SemcEmail..."
            xospapps_essentials_SemcEmail="essentials/SemcEmail/SemcEmail.apk"
            if [[ $(md5sum ${xospapps_essentials_SemcEmail} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_SemcEmail}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_SemcEmail}
                    mkdir essentials/SemcEmail
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_SemcEmail} -O ${xospapps_essentials_SemcEmail} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading textinput-tng..."
            xospapps_essentials_arm_textinputtng="essentials/textinput-tng/textinput-tng.apk"
            xospapps_essentials_arm_textinputtng_libswiftkeysdkjava="essentials/textinput-tng/lib/arm/libswiftkeysdk-java.so"
            xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava="essentials/textinput-tng/lib/arm64/libswiftkeysdk-java.so"
            if [[ $(md5sum ${xospapps_essentials_arm_textinputtng} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_arm_textinputtng}.md5 |cut -f 1 -d "%") && $(md5sum ${xospapps_essentials_arm_textinputtng_libswiftkeysdkjava} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_arm_textinputtng_libswiftkeysdkjava}.md5 |cut -f 1 -d "%") && $(md5sum ${xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_arm_textinputtng}
                    rm -f ${xospapps_essentials_arm_textinputtng_libswiftkeysdkjava}
                    rm -f ${xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava}
                    mkdir -p essentials/textinput-tng/lib/arm
                    mkdir -p essentials/textinput-tng/lib/arm64
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_arm_textinputtng} -O ${xospapps_essentials_arm_textinputtng} &>/dev/null && wget -t 2 ${xospappsessentials}/${xospapps_essentials_arm_textinputtng_libswiftkeysdkjava} -O ${xospapps_essentials_arm_textinputtng_libswiftkeysdkjava} && wget -t 2 ${xospappsessentials}/${xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava} -O ${xospapps_essentials_arm64_textinputtng_libswiftkeysdkjava} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading Xperia Services..."
            xospapps_essentials_XperiaServices="essentials/XperiaServices/XperiaServices.apk"
            if [[ $(md5sum ${xospapps_essentials_XperiaServices} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_XperiaServices}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_XperiaServices}
                    mkdir essentials/XperiaServices
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_XperiaServices} -O ${xospapps_essentials_XperiaServices} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading Sony BatteryAdviser..."
            xospapps_essentials_BatteryAdviser="essentials/BatteryAdviser/BatteryAdviser.apk"
            xospapps_essentials_arm_BatteryAdviser_libpbp="essentials/BatteryAdviser/lib/arm/libpbp.so"
            xospapps_essentials_arm64_BatteryAdviser_libpbp="essentials/BatteryAdviser/lib/arm64/libpbp.so"
            if [[ $(md5sum ${xospapps_essentials_BatteryAdviser} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_BatteryAdviser}.md5 |cut -f 1 -d "%") && $(md5sum ${xospapps_essentials_arm_BatteryAdviser_libpbp} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_arm_BatteryAdviser_libpbp}.md5 |cut -f 1 -d "%") && $(md5sum ${xospapps_essentials_arm64_BatteryAdviser_libpbp} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_arm64_BatteryAdviser_libpbp}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_BatteryAdviser}
                    rm -f ${xospapps_essentials_arm_BatteryAdviser_libpbp}
                    rm -f ${xospapps_essentials_arm64_BatteryAdviser_libpbp}
                    mkdir -p essentials/BatteryAdviser/lib
                    mkdir essentials/BatteryAdviser/lib/arm
                    mkdir essentials/BatteryAdviser/lib/arm64
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_BatteryAdviser} -O ${xospapps_essentials_BatteryAdviser} &>/dev/null && wget -t 2 ${xospappsessentials}/${xospapps_essentials_arm_BatteryAdviser_libpbp} -O ${xospapps_essentials_arm_BatteryAdviser_libpbp} &>/dev/null && wget -t 2 ${xospappsessentials}/${xospapps_essentials_arm64_BatteryAdviser_libpbp} -O ${xospapps_essentials_arm64_BatteryAdviser_libpbp} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading ClockWidgets ..."
            xospapps_essentials_ClockWidgets="essentials/ClockWidgets/ClockWidgets.apk"
            if [[ $(md5sum ${xospapps_essentials_ClockWidgets} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_ClockWidgets}.md5 |cut -f 1 -d "%") ]]
                then
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_ClockWidgets}
                    mkdir essentials/ClockWidgets
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_ClockWidgets} -O ${xospapps_essentials_ClockWidgets} &>/dev/null
                        then
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            echo -e "Downloading Pardana Files..."
            xospapps_essentials_PardanaFiles="essentials/PardanaFiles.zip"
            xospapps_essentials_PardanaFiles_extracted="essentials/PardanaFiles"
            if [[ $(md5sum ${xospapps_essentials_PardanaFiles} |cut -f 1 -d " " |tr '[:lower:]' '[:upper:]') == $(curl ${xospappsessentials}/${xospapps_essentials_PardanaFiles}.md5 |cut -f 1 -d "%") ]]
                then
                    rm -fr ${xospapps_essentials_PardanaFiles_extracted}
                    mkdir ${xospapps_essentials_PardanaFiles_extracted}
                    unzip -q ${xospapps_essentials_PardanaFiles} -d ${xospapps_essentials_PardanaFiles_extracted}
                    xospapps_essentials_done
                else
                    rm -f ${xospapps_essentials_PardanaFiles}
                    rm -fr ${xospapps_essentials_PardanaFiles_extracted}
                    mkdir ${xospapps_essentials_PardanaFiles_extracted}
                    if wget -t 2 ${xospappsessentials}/${xospapps_essentials_PardanaFiles} -O ${xospapps_essentials_PardanaFiles} &>/dev/null
                        then
                            unzip -q ${xospapps_essentials_PardanaFiles} -d ${xospapps_essentials_PardanaFiles_extracted}
                            xospapps_essentials_done
                        else
                            xospapps_essentials_dwnlderror
                    fi
            fi
            cd ..
        else
            echo -e "Environment isn't connected to internet, please check your connection."
            exit 0
    fi
}


function installboot()
{
    if [ ! -e "$OUT/recovery/root/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/boot.img" ];
    then
        echo "No boot.img found. Run make bootimage first."
        return 1
    fi
    PARTITION=`grep "^\/boot" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine boot partition."
            return 1
        fi
    fi
    adb start-server
    adb wait-for-online
    adb root
    sleep 1
    adb wait-for-online shell mount /system 2>&1 > /dev/null
    adb wait-for-online remount
    if (adb shell getprop ro.xosp.device | grep -q "$XOSP_BUILD");
    then
        adb push $OUT/boot.img /cache/
        for i in $OUT/system/lib/modules/*;
        do
            adb push $i /system/lib/modules/
        done
        adb shell dd if=/cache/boot.img of=$PARTITION
        adb shell chmod 644 /system/lib/modules/*
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $XOSP_BUILD, run away!"
    fi
}

function installrecovery()
{
    if [ ! -e "$OUT/recovery/root/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/recovery.img" ];
    then
        echo "No recovery.img found. Run make recoveryimage first."
        return 1
    fi
    PARTITION=`grep "^\/recovery" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine recovery partition."
            return 1
        fi
    fi
    adb start-server
    adb wait-for-online
    adb root
    sleep 1
    adb wait-for-online shell mount /system 2>&1 >> /dev/null
    adb wait-for-online remount
    if (adb shell getprop ro.xosp.device | grep -q "$XOSP_BUILD");
    then
        adb push $OUT/recovery.img /cache/
        adb shell dd if=/cache/recovery.img of=$PARTITION
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $XOSP_BUILD, run away!"
    fi
}

function mms() {
    local T=$(gettop)
    if [ -z "$T" ]
    then
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return 1
    fi

    case `uname -s` in
        Darwin)
            local NUM_CPUS=$(sysctl hw.ncpu|cut -d" " -f2)
            ONE_SHOT_MAKEFILE="__none__" \
                make -C $T -j $NUM_CPUS "$@"
            ;;
        *)
            local NUM_CPUS=$(cat /proc/cpuinfo | grep "^processor" | wc -l)
            ONE_SHOT_MAKEFILE="__none__" \
                mk_timer schedtool -B -n 1 -e ionice -n 1 \
                make -C $T -j $NUM_CPUS "$@"
            ;;
    esac
}

function repolastsync() {
    RLSPATH="$ANDROID_BUILD_TOP/.repo/.repo_fetchtimes.json"
    RLSLOCAL=$(date -d "$(stat -c %z $RLSPATH)" +"%e %b %Y, %T %Z")
    RLSUTC=$(date -d "$(stat -c %z $RLSPATH)" -u +"%e %b %Y, %T %Z")
    echo "Last repo sync: $RLSLOCAL / $RLSUTC"
}

function reposync() {
    case `uname -s` in
        Darwin)
            repo sync -j 4 "$@"
            ;;
        *)
            schedtool -B -n 1 -e ionice -n 1 `which repo` sync -j 4 "$@"
            ;;
    esac
}

function repodiff() {
    if [ -z "$*" ]; then
        echo "Usage: repodiff <ref-from> [[ref-to] [--numstat]]"
        return
    fi
    diffopts=$* repo forall -c \
      'echo "$REPO_PATH ($REPO_REMOTE)"; git diff ${diffopts} 2>/dev/null ;'
}

# Return success if adb is up and not in recovery
function _adb_connected {
    {
        if [[ "$(adb get-state)" == device &&
              "$(adb shell test -e /sbin/recovery; echo $?)" != 0 ]]
        then
            return 0
        fi
    } 2>/dev/null

    return 1
};

alias mmp='dopush mm'
alias mmmp='dopush mmm'
alias mmap='dopush mma'

function fixup_common_out_dir() {
    common_out_dir=$(get_build_var OUT_DIR)/target/common
    target_device=$(get_build_var TARGET_DEVICE)
    if [ ! -z $CM_FIXUP_COMMON_OUT ]; then
        if [ -d ${common_out_dir} ] && [ ! -L ${common_out_dir} ]; then
            mv ${common_out_dir} ${common_out_dir}-${target_device}
            ln -s ${common_out_dir}-${target_device} ${common_out_dir}
        else
            [ -L ${common_out_dir} ] && rm ${common_out_dir}
            mkdir -p ${common_out_dir}-${target_device}
            ln -s ${common_out_dir}-${target_device} ${common_out_dir}
        fi
    else
        [ -L ${common_out_dir} ] && rm ${common_out_dir}
        mkdir -p ${common_out_dir}
    fi
}


# Android specific JACK args
if [ -n "$JACK_SERVER_VM_ARGUMENTS" ] && [ -z "$ANDROID_JACK_VM_ARGS" ]; then
    export ANDROID_JACK_VM_ARGS=$JACK_SERVER_VM_ARGUMENTS
fi
