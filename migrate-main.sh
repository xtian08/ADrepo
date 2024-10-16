#!/bin/bash

##########################################################################################
##
##Copyright (c) 2017 Jamf.  All rights reserved.
##
##      Redistribution and use in source and binary forms, with or without
##      modification, are permitted provided that the following conditions are met:
##              * Redistributions of source code must retain the above copyright
##                notice, this list of conditions and the following disclaimer.
##              * Redistributions in binary form must reproduce the above copyright
##                notice, this list of conditions and the following disclaimer in the
##                documentation and#or other materials provided with the distribution.
##              * Neither the name of the Jamf nor the names of its contributors may be
##                used to endorse or promote products derived from this software without
##                specific prior written permission.
##
##      THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
##      EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
##      WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
##      DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
##      DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
##      (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
##      LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
##      ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
##      (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
##      SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##
##########################################################################################
#
# SUPPORT FOR THIS PROGRAM
#
#       This program is distributed "as is" by JAMF Software, Professional Services Team. For more
#       information or support for this script, please contact your JAMF Software Account Manager.
#
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME - apiMDM_remove.sh
#
# DESCRIPTION - Script is used to remove MDM from macOS clients 10.13 (High Sierra) and later.
#               Parameters passed to the script include a Jamf server username and password and
#               optionally the Jamf server URL in the form: https://FQDN:port/.
#
#               The jamf user aaccount must have at least computer create and read (JSS Objects)
#               along with Send Computer Unmanage Command (JSS Actions).
#
####################################################################################################
#
# HISTORY
#
#    Version: 1.4
#
#   - Created by Leslie Helou, Professional Services Engineer, JAMF Software on December 12, 2017
#   - updated 20190124: Provide additional feedback as it runs
#   - updated 20200918: Updates due to changes in xpath for Big Sur
#   - updated 20240726: Update to use token for authentication
#
####################################################################################################

## check run settings for arguments

## get macOS version
macOS_Version=$(sw_vers -productVersion)
majorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $1}' )
minorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $2}' )

## account with computer create and read (JSS Objects), Send Computer Unmanage Command (JSS Actions)
uname="apimdmremove"
pwd="!Welcome20"

if [ "$uname" == "" ];then
    echo "missing client ID - exiting."
    exit 1
fi

if [ "$pwd" == "" ];then
    echo "missing client secret - exiting."
    exit 1
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
    exit 1
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
    exit 1
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
    exit 1
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

