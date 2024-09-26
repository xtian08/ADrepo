##############################PS
$psexecUrl = "https://github.com/xtian08/ADrepo/raw/main/PsExec.exe"
$psexecPath = "C:\temp\psexec.exe"
$simulateInstall = $false  # Set to $true to simulate installation, $false to perform actual installation

if (-Not (Test-Path $psexecPath)) {
    if (-Not (Test-Path "C:\temp")) { New-Item -Path "C:\temp" -ItemType Directory }
    Invoke-WebRequest -Uri $psexecUrl -OutFile $psexecPath
}

$windowsAppsPath = "$env:ProgramFiles\WindowsApps"
$wingetPath = Get-ChildItem -Path $windowsAppsPath -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
##############################PS

if ($wingetPath) {
    Write-Output "winget.exe found at: $wingetPath"
    $logFilePath = "c:\temp\zoom.log"
    #New-Item c:\temp\zoom.log -type file

    # Winget args
    $wingetCommand = "`"$wingetPath`" show zoom.zoom --accept-source-agreements --disable-interactivity"
    #echo $wingetCommand
    
    #Start-Process -FilePath $psexecPath -ArgumentList "/accepteula -i 1 -s cmd /c $wingetCommand > $logFilePath 2>&1" -PassThru -Wait -NoNewWindow
    Start-Process -FilePath $psexecPath -ArgumentList "/accepteula -i 1 -s cmd /c $wingetCommand > `"$logFilePath`" 2>&1" -PassThru -Wait -NoNewWindow


    # Read the log file and extract the Version value
    $zversion = Select-String -Path $logFilePath -Pattern 'Version:\s*(\S+)' | ForEach-Object {
        if ($_.Matches.Count -gt 0) { return $_.Matches[0].Groups[1].Value }
    }
    
} else {
    Write-Output "winget.exe not found on the system."
    return 1
}

function Zinstall {

    $osArchitecture = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    write-output "Detected OS architecture: $osArchitecture"

    switch ($osArchitecture) {
        "64-bit" { $installerUrl = "https://zoom.us/client/6.2.0.46690/ZoomInstallerFull.msi?archType=x64" }
        "32-bit" { $installerUrl = "https://zoom.us/client/6.2.0.46690/ZoomInstallerFull.msi" }
        default { $installerUrl = "https://zoom.us/client/6.2.0.46690/ZoomInstallerFull.msi?archType=winarm64" }
    }

    if ($simulateInstall) {
        write-output "Simulating Zoom installation from $installerUrl"
    } else {
        $installerPath = "$env:TEMP\ZoomInstaller.msi"
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($installerUrl, $installerPath)
        $client.Dispose()
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /qn /norestart MSIRestartManagerControl=Disable" -Wait
        Write-Output "Zoom has been installed"
    }
}

# Check if Zoom is installed
$zoomInstalled = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*Zoom*"}
if ($zoomInstalled) {
    write-output "Zoom is installed"
    $izversion = $zoomInstalled.Version.Trim()
    #$izversion = "6.1"
    write-output "Installed Zoom version is $izversion"
    
    if ($izversion -ge $zversion) {
        write-output "Zoom latest or newer."
        exit 0
    } else {
        write-output "Zoom is outdated."
        Zinstall
    }
} else {
    write-output "Zoom not found. Installing..."
    Zinstall
}
