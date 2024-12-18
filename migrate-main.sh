#!/bin/bash

# Define attributes
outshow=$(sudo -S profiles show -type enrollment | grep -q "ds1688" && echo "WS1 link found" || echo "Not on WS1")
outstatus=$(sudo -S profiles status -type enrollment)
jamfsrv="https://nyuad.jamfcloud.com/mdm/ServerURL"
ws1srv="https://ds1688.awmdm.com/DeviceServices/AppleMDM/Processor.aspx"

# Show output
echo "Pshow: $outshow"
echo "Pstatus: $outstatus"

# Capture output
enroll_1=$(echo "$outstatus" | awk '/Enrolled via DEP:/ {print $4}')
enroll_2=$(echo "$outstatus" | awk '/MDM enrollment:/ {print $3}')
enroll_3=$(echo "$outstatus" | awk '/MDM server:/ {print $3}')

# Check conditions
if [[ $enroll_3 == *"jamfcloud"* ]]; then
    echo "Asset is on Jamf"
    echo "Condition met: proceeding to migrate"
elif [[ $outshow == *"ds1688"* ]] && [[ $enroll_1 == "Yes" && $enroll_2 == "Yes" && $enroll_3 == "$ws1srv" ]]; then
    echo "Already WS1 DEP enrolled"
    exit 0
elif [[ $outshow == *"ds1688"* ]] && [[ $enroll_1 == "No" && $enroll_2 == "No" ]]; then
    echo "Asset is not enrolled but is on WS1 DEP"
    echo "Condition met: proceeding to migrate"
elif [[ $enroll_2 == "Yes" && $enroll_3 == "$ws1srv" ]]; then
    echo "Found enrolled on WS1 manually"
    exit 0
elif [[ $enroll_2 == "No" ]]; then
    echo "Asset is not enrolled"
    echo "Condition met: proceeding to migrate"
fi

# Migrate to Jamf - MAIN Code - Do not modify

#Download and Install Base64 pkg
u_file="/Users/Shared/package.pkg"
p_file="/Library/LaunchAgents/com.erikng.umad.plist"
p_file_url="https://github.com/NYUAD-IT/NYU-umad/raw/main/payload/Library/LaunchAgents/com.erikng.umad.plist"

downb64() {
echo "Downloading Base64 pkg"
curl -L -o $u_file "https://github.com/NYUAD-IT/NYU-umad/raw/main/umad-2.0-Signed.pkg" 

}

# if /Users/Shared/umad.pkg not exit then download pkg
if [ ! -f $u_file ]; then
    downb64
else
    echo "Base64 pkg already exists"
fi

if [ -d "/Library/umad" ]; then
    echo "Enrollment already in progress"
else
    sudo installer -pkg $u_file -target / #&& rm $u_file
fi

#Update LaunchAgent
sudo curl -L -o $p_file $p_file_url
#Fix permissions
sudo chown $(whoami) /Library/LaunchAgents/com.erikng.umad.plist
sudo chown $(whoami) /Library/LaunchDaemons/com.erikng.umad.check_dep_record.plist
sudo chown $(whoami) /Library/LaunchDaemons/com.erikng.umad.trigger_nag.plist
sudo chown $(whoami) /Library/umad

## get macOS version
macOS_Version=$(sw_vers -productVersion)
majorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $1}' )
minorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $2}' )

## account with computer create and read (JSS Objects), Send Computer Unmanage Command (JSS Actions)
uname="apimdmremove"
pwd="!Welcome20"

if [ "$uname" == "" ];then
    echo "missing client ID - exiting."
fi

if [ "$pwd" == "" ];then
    echo "missing client secret - exiting."
fi

if [ "https://nyuad.jamfcloud.com/" != "" ];then
    server="https://nyuad.jamfcloud.com/"
    echo "Server is $server"
else
    ## get current Jamf Pro server
    server=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
    echo "using server read from com.jamfsoftware.jamf.plist: ${server}"
fi

if [ "$server" == "" ];then
    echo "unable to determine current Jamf Pro server - exiting."
fi

## ensure the server URL ends with a /
strLen=$((${#server}-1))
lastChar="${server:$strLen:1}"
if [ ! "$lastChar" = "/" ];then
    server="${server}/"
fi

## get unique identifier for machine
udid=$(/usr/sbin/system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }')
if [ "$udid" == "" ];then
    echo "unable to determine UUID of computer - exiting."
else
    echo "computer UUID: $udid"
fi

## get token
tokenURL="${server}api/oauth/token"
tokenURL="${server}api/v1/auth/token"
echo $tokenURL

clientString="grant_type=client_credentials&client_id=$uname&client_secret=$pwd"

response=$(curl -s -u "$uname":"$pwd" "$tokenURL" -X POST)
bearerToken=$(echo "$response" | plutil -extract token raw -)
echo "$bearerToken"

## get computer ID from Jamf server
echo "get computer ID: curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H \"Accept: application/xml\" -H \"Authorization: Bearer $(echo $bearerToken | head -n15)...\""
compXml=$(/usr/bin/curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H "Accept: application/xml" -H "Authorization: Bearer $bearerToken")
echo "computer record: ${compXml}"

if [[ $(echo "${compXml}" | grep "The server has not found anything matching the request URI") == "" ]];then
    if [ $majorVer -gt 10 ] || ([ $majorVer eq 10 ] && [ $majorMinor -gt 15 ]);then
        compId=$(echo "${compXml}" | /usr/bin/xpath -q -e "//computer/general/id/text()")
    else
        compId=$(echo "${compXml}" | /usr/bin/xpath "//computer/general/id/text()")
    fi
    echo "computer ID: $compId"
else
    echo "computer was not found on $server - exiting."
fi

## send unmanage command to machine
echo "unmanage machine: curl -m 20 -s ${server}JSSResource/computercommands/command/UnmanageDevice/id/${compId} -X POST -H \"Authorization: Bearer $(echo $bearerToken | head -n15)...\""
/usr/bin/curl -m 20 -s ${server}JSSResource/computercommands/command/UnmanageDevice/id/${compId} -X POST -H "Authorization: Bearer $bearerToken"

##invalidate token
responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $server/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
if [[ ${responseCode} == 204 ]]
then
    echo "Token successfully invalidated"
    bearerToken=""
    tokenExpirationEpoch="0"
elif [[ ${responseCode} == 401 ]]
then
    echo "Token already invalid"
else
    echo "An unknown error occurred invalidating the token"
fi

#Reload UMAD LaunchAgent
sleep 15
sudo launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.erikng.umad.plist
sudo launchctl bootstrap gui/$(id -u) /Library/LaunchAgents/com.erikng.umad.plist

#Open Profiles Syspref
#open /System/Library/PreferencePanes/Profiles.prefPane

sleep 30

# Get the currently logged-in user
loggedInUser=$(stat -f "%Su" /dev/console)

# Get the serial number of the Mac
serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}')

# Create the CSV file and write the information
echo "Serial Number,Username" > /Users/Shared/owner.csv
echo "$serialNumber,$loggedInUser" >> /Users/Shared/owner.csv

# Print a success message
echo "Owner information captured and saved to /Users/Shared/owner.csv"

