#!/bin/bash


ANDROID=/data/opt/android

ANDROID_SDK_HOME=$ANDROID $ANDROID/sdk/emulator/emulator -avd SeqStudio -no-snapshot
