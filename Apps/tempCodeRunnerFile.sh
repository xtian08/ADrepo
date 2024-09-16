ps -A | grep -i "Zoom.us.app" | grep -v "grep" > /tmp/RunningApps.txt

if grep -qi "Zoom.us.app" /tmp/RunningApps.txt; then
    echo "****** Application is currently running on target Mac. Exiting. ******"
    exit 0
else
    echo "****** Application is not running on target Mac. Proceeding Clean Install... ******"
    sudo rm -rf /Applications/zoom.us.app
fi