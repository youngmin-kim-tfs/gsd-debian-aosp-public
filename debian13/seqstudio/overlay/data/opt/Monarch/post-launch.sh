#!/bin/bash


ANDROID=/data/opt/android
ADB=$ANDROID/sdk/platform-tools/adb
APK=/data/opt/Monarch/DataCollection-release-1.10-1-6317120.apk
JAR=/data/opt/Monarch/3200.jar
FIRST_FLAG=$ANDROID/.launched_before

sleep 2
systemctl --user start splash

start_emulator() {
    $ADB wait-for-device
    if [ $? -ne 0 ]; then
        echo "Timeout waiting for emulator"
        exit 1
    fi

    echo "Emulator detected, waiting for boot complete..."
    systemctl --user restart splash

    until [ "$($ADB -e shell getprop init.svc.bootanim 2>&1)" = "stopped" ] ||
        [ "$($ADB -e shell getprop dev.bootcomplete 2>&1)" = "1" ]; do
        sleep 2
        echo "...waiting for boot complete"
    done

    echo "Emulator booted!"
}

set_props() {
    $ADB -e root 2>/dev/null
    sleep 2

    $ADB -e shell pm disable com.android.systemui
    if [ $? -eq 0 ]; then
        touch "$FIRST_FLAG"
	echo "systemui disabled"
    else
        echo "Failed to disable systemui"
    fi

    $ADB -e shell setprop dalvik.vm.heapsize 768m
    if [ $? -eq 0 ]; then
        echo "vm.heap to 768m"
    else
        echo "Failed to set vm.heapsize"
    fi
}

start_emulator
set_props

# Check if first boot
if [ ! -f "$FIRST_FLAG" ]; then
    echo "Install $APK"
    sleep 2
    $ADB install $APK
    if [ $? -eq 0 ]; then
        echo "$APK installed"
    else
        echo "Failed to install $APK"
    fi
    touch "$FIRST_FLAG"
    # reboot the emulator
    $ADB reboot
    sleep 10
    start_emulator
    set_props
fi

# start 3200.jar
pkill -f "$JAR" 2>/dev/null
java -jar "$JAR" &

# start the mainapp
$ADB shell am start com.lifetech.monarch.mainapp/.SplashActivity

sleep 2
systemctl --user stop splash


