#!/bin/bash


ANDROID=/data/opt/android
ADB=$ANDROID/sdk/platform-tools/adb
APK=/data/opt/Monarch/DataCollection-release-1.10-1-6317120.apk
JAR=/data/opt/Monarch/3200.jar
FIRST_FLAG=$ANDROID/.launched_before

pkill -f qemu 2>/dev/null
pkill -f "$JAR" 2>/dev/null

cd $ANDROID

start_emulator() {
    ANDROID_SDK_HOME=$ANDROID $ANDROID/sdk/emulator/emulator -avd SeqStudio -no-snapshot &
    EMULATOR_PID=$!

    $ADB wait-for-device
    if [ $? -ne 0 ]; then
        echo "Timeout waiting for emulator"
        kill $EMULATOR_PID 2>/dev/null || true
        exit 1
    fi

    echo "Emulator detected, waiting for boot complete..."

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
    $ADB install $APK
    if [ $? -eq 0 ]; then
        echo "$APK installed"
    else
        echo "Failed to install $APK"
	exit 1
    fi
    # restart the emulator
    pkill -f qemu 2>/dev/null
    start_emulator
    set_props
fi
sleep 2

# start 3200.jar
java -jar "$JAR" &

# start the mainapp
$ADB shell am start com.lifetech.monarch.mainapp/.SplashActivity


