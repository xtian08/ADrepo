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

    # Winget args
    $wingetCommand = "`"$wingetPath`" show zoom.zoom --accept-source-agreements --disable-interactivity"
    echo $wingetCommand
    
    $process = Start-Process -FilePath $psexecPath -ArgumentList "/accepteula -i 1 -s cmd /c $wingetCommand > $logFilePath 2>&1" -PassThru -Wait -NoNewWindow 

    # Read the log file and extract the Version value
    $zversion = Select-String -Path $logFilePath -Pattern 'Version:\s*(\S+)' | ForEach-Object {
        if ($_.Matches.Count -gt 0) { return $_.Matches[0].Groups[1].Value }
    }
    
} else {
    Write-Output "winget.exe not found on the system."
    return 1
}

function Zinstall {
    if ($simulateInstall) {
        write-output "Simulating Zoom installation"
    } else {
        $wingetCommand = "`"$wingetPath`" install --id Zoom.Zoom --silent --accept-package-agreements --accept-source-agreements -e"
        echo $wingetCommand 
        Start-Process -FilePath $psexecPath -ArgumentList "-i 1 -s cmd /c $wingetCommand > $logFilePath 2>&1" -Wait -NoNewWindow
    }
}

# Check if Zoom is installed
$zoomInstalled = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*Zoom*"}
if ($zoomInstalled) {
    write-output "Zoom is installed"
    $izversion = $zoomInstalled.Version.Trim()
    write-output "Installed Zoom version is $izversion"
    
    # Compare the versions (ensuring both are trimmed)
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
