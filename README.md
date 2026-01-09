# gsd-debian-aosp

## IS data prep:
  1. Login as root
  2. Create a folder, /data/SpectrometerData
  3. Copy all *.csv.gz to /data/SpectrometerData
  4. Telnet to IS console:
  	 + telnet localhost 2323
  5. Check *.csv.gz files are listed:
  	 + FILE:LIST? spectrodata:

## J6 Calibration:
  ### IS:
  1. Open IS console
     + telnet localhost 2323
  2. In IS console
     + ADMIN
     + DA:LOAD spectrodata:calib_J6.csv.gz
  
  ### eGUI:
  1. Open eGUI
  2. Login
  3. If 'Full optical alignment failed', just close the error dialog
     + Open IS console (telnet localhost 2323) and type:
       - S= Capillary:Aligned True
       - S= Laser:Normalized True
  4. Go to 'Settings -> Maintenance and service -> Calibration -> Dye calibration'
  5. Tap 'A01' to select A01-D1 wells
  6. Tap 'Dye set' button
  7. Select 'Matrix standard' tab
  8. Select 'J6(DS-36)' from the list
  9. Tap 'Calibrate'
  10. Tap 'Continue run' if warning is shown
  11. Wait for the run to complete
  12. Tap 'Results'
  13. Check 'Result' column is showong all 'Passed'
  14. Tap 'Done' and then 'Continue' to go back to home screen
  15. Pull the log out from the emulator:
      + adb root
      + adb pull /data/data/com.lifetech.monarch.mainapp/cache/dc.log ./
  16. Rename dc.log to dc_J6_calib.log

## Regular Fragment Run:
  1. Login and go to home
  2. Tap 'Setup Run'
  3. Tap 'Create new plate setup'
  4. In 'Plate Perperties', check 'Fragment analysis' is selected for 'Application'
  5. Tap 'Plate' tab
  6. Tap 'A01' on the plate layout to select A01-D01
  7. Tap 'Edit' button
  8. Tap 'Run module' dropdown and select 'FragAnalysis'
  9. Tap 'Size standard' dropdown and select 'GS600LIZ'
  10. Tap 'Dye set' dropdown and select 'G5(DS-33)'
  11. Tap 'Done' to go back to 'Plate Properties'
  12. Open IS console (telnet localhost 2323) and type:
      + DA:LOAD spectrodata:frag_J6_GS600.csv.gz
  13. Tap 'Start run'
  14. Tap 'OK' to continue
  15. Tap 'Continue run' if 'Consumable Warning' dialog shows
  16. Tap 'A1' circle to display the realtime plot
  17. Close the plot after all data are collected.
  18. Tap 'Results' in 'Run Complete' circle to see the result table.
  19. Tap 'Done'
  20. Tap 'Home' and 'Continue' to go back to home
  21. Pull the log out from the emulator:
      + adb root
      + adb pull /data/data/com.lifetech.monarch.mainapp/cache/dc.log ./
  16. Rename dc.log to dc_J6_frag.log

## Changing IS IP address in eGUI
  1. adb root
  2. adb shell
  3. cd /data/data/com.lifetech.monarch.mainapp/shared_prefs
  4. vi com.lifetech.monarch.mainapp_preferences.xml
  5. go to \<string name="instrument_server_ip_address_pref_key"\>10.0.2.2\</string\>
  6. Change the IP address to a new IP address
  7. Save and exit vi
  8. chmod 666 com.lifetech.monarch.mainapp_preferences.xml

## IS on Windows Ubuntu
  1. Open Ubuntu shell on Windows and obtain the Ubuntu IP address, e.g. 172.20.40.231
  2. Install IS on Ubuntu and follow the above 'IS data prep'
  3. Allow Inbound for ports 2323 and 7000 in Windows Firewall
  4. Open Windows Powershell and enable portproxy
     + netsh interface portproxy v4tov4 listenport=2323 listenaddress=0.0.0.0 connectport=2323 connectaddress=172.20.40.231
     + netsh interface portproxy v4tov4 listenport=7000 listenaddress=0.0.0.0 connectport=7000 connectaddress=172.20.40.231
     + netsh interface portproxy show all
     + netsh interface portproxy reset ---> to stop
  5. Start the IS
     + sudo python2 instrument.py
