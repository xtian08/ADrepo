#!/bin/bash
#Created by Chris Mariano
#Description: Zoom Install Script

mkdir /tmp/zoom
cd /tmp/zoom

# Get latest version
cask_json="zoom.json"
latest_json=$(curl -s "https://formulae.brew.sh/api/cask/$cask_json")
latestver=$(echo "$latest_json" | grep -o '"version":"[^"]*"' | awk -F'"' '{print $4}')
echo "Latest Version is: $latestver"

# Update if not latest
if [ -e "/Applications/zoom.us.app" ]; then
    currentinstalledver=`/usr/bin/defaults read /Applications/zoom.us.app/Contents/Info CFBundleVersion | sed -e 's/0 //g' -e 's/(//g' -e 's/)//g'`
    echo "Current installed version is: $currentinstalledver"
        if [ ${latestver} = ${currentinstalledver} ]; then
            echo "Zoom is up-to-date. Exiting."
            exit 0
        fi
    else
        currentinstalledver="none"
        echo "Zoom is not installed..."
fi

check_running_ap() {
ps -A | grep -i "zoom.us.app" | grep -v "grep" > /tmp/RunningApps.txt

if grep -qi "zoom.us.app" /tmp/RunningApps.txt; then
    echo "****** Application is currently running on target Mac. Exiting. ******"
    exit 0
else
    echo "****** Application is not running on target Mac. Proceeding Clean Install... ******"
    sudo rm -rf /Applications/zoom.us.app
fi
}

#Get Architecture
mxarch=$(uname -m)
#mxarch="arm64"
echo "Arch is: ${mxarch}"

#Install on ARM
if [[ "${currentinstalledver}" != "${latestver}" ]] && [[ "${mxarch}" == "arm64" ]]; then
echo "Installing Zoom for ARM"
curl -L -o zoomARM.pkg https://cdn.zoom.us/prod/${latestver}/arm64/zoomusInstallerFull.pkg
curl -L -o us.zoom.config.plist https://raw.githubusercontent.com/xtian08/cyrepo/master/us.zoom.config.plist
check_running_ap
sudo -S installer -allowUntrusted -pkg "/tmp/zoom/zoomARM.pkg" -target /;

#Install on Intel
elif [[ "${currentinstalledver}" != "${latestver}" ]] && [[ "$mxarch" == "x86_64" ]]; then
echo "Installing Zoom for Intel"
curl -L -o zoomX86.pkg https://cdn.zoom.us/prod/${latestver}/Zoom.pkg
curl -L -o us.zoom.config.plist https://raw.githubusercontent.com/xtian08/cyrepo/master/us.zoom.config.plist
check_running_ap
sudo -S installer -allowUntrusted -pkg "/tmp/zoom/zoomX86.pkg" -target /;
fi

#Remove Temp Files
sudo rm -rf /tmp/zoom/


