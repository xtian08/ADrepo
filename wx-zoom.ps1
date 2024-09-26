##############################PS
$simulateInstall = $false  # Set to $true to simulate installation, $false to perform actual installation
$taskName = "SilentWingetTask"
$logFilePath = "C:\temp\zoomV.log"
$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
$wingetCommand = "`"$wingetPath`" show zoom.zoom --accept-source-agreements --disable-interactivity"
$command = "/c $wingetCommand > $logFilePath 2>&1"

# Create task action to execute the command and log output
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $command
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$task = New-ScheduledTask -Action $action -Principal $principal

# Register and run the task
Register-ScheduledTask -TaskName $taskName -InputObject $task
Start-ScheduledTask -TaskName $taskName

# Wait for task completion and delete the task
Start-Sleep -Seconds 10
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

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


Start-Sleep -Seconds 30
