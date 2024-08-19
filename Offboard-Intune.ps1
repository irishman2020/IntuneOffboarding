# Take device from AD joined Intune managed state and ready for hybrid join / Intune enrolled in new tenant

# log function
function log()
{
  [Cmdletbinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$message
  )
  $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss tt"
  Write-Output "$time - $message"
}

# Intune cert path
$intuneCert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Issuer -match "Microsoft Intune MDM Device CA"}

# Remove if present
$mdm = $false
if($intuneCert)
{
  $mdm = $true
  log "Found Intune certificate.  Attempting to remove..."
  try
  {
    Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Issuer -match "Microsoft Intune MDM Device CA"} | Remove-Item -Force  
    log "Removed Intune certificate"
  }
  catch
  {
    $message = $_.ExceptionMessage
    log "Failed to remove Intune certificate: $($message)"
  }
}
else
{
  log "$($env:hostname) is not managed with Intune"
}

# Remove all previous enrollment registry entries
if($mdm -eq $true)
{
  log "Removing MDM enrollment..."
    $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
    $enrollments = Get-ChildItem -Path $enrollmentPath
    foreach($enrollment in $enrollments)
    {
        $object = Get-ItemProperty Registry::$enrollment
        $enrollPath = $enrollmentPath + $object.PSChildName
        $key = Get-ItemProperty -Path $enrollPath -Name "DiscoveryServiceFullURL"
        if($key)
        {
            log "Removing MDM enrollment $($enrollPath)..."
            Remove-Item -Path $enrollPath -Recure
            log "MDM enrollment removed successfully."
        }
        else
        {
            log "MDM enrollment not present."
        }
    }
    $enrollId = $enrollPath.Split("\")[-1]
    $additionalPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provinsioning\OMADM\Accounts\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger\$($enrollID)",
        "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions\$($enrollID)"
    )
    foreach($path in $additionalPaths)
    {
        if(Test-Path $path)
        {
            log "Removing $($path)..."
            Remove-Item -Path $path -Recurse
            log "$($path) removed successfully."
        }
        else
        {
            log "$($path) not present."
        }
    }
}
else
{
  log "$($env:HOSTNAME) is not managed with Intune."
}

# Stop current processes
$processes = @(
  "ms-teams",
  "Outlook",
  "OneDrive"
)

foreach($process in $processes)
{
  Stop-Process -Name $process -Force -ErrorAction SilentlyContinue
}

# Get user info
$currentUser = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object UserName).UserName
$currentUserTruncated = currentUser.Split("\")[-1]
$sid = (New-Object System.Security.Principal.NTAccount($currentUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value
$profilePath = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($sid)" -Name "ProfileImagePath")

################ Clear teams cache ################################


#Stop Teams process 
Get-Process -ProcessName ms-Teams -ErrorAction SilentlyContinue | Stop-Process -Force 
Start-Sleep -Seconds 3
Write-Host "Teams Process Sucessfully Stopped" 

#Clear Team Cache
try{
Get-ChildItem -Path "C:\Users\$currentUserTruncated\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache" | Remove-Item -Recurse

Write-Host "Teams Cache Cleaned" 
}catch{
echo $_ 
}

#Remove Credential from Credential manager
$credential = cmdkey /list | ForEach-Object{if($_ -like "*Target:*" -and $_ -like "*msteams*"){cmdkey /del:($_ -replace " ","" -replace "Target:","")}}

#Remove Reg.Key
$Regkeypath= "HKCU:\Software\Microsoft\Office\Teams" 
$value = (Get-ItemProperty $Regkeypath).HomeUserUpn -eq $null
If ($value -eq $False) 
{ 
  Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Office\Teams" -Name "HomeUserUpn"
  Write-Host "The registry value Sucessfully removed" 
} 
Else { Write-Host "The registry value does not exist"}

#Try to remove the Link School/Work account if there was one. It can be created if the first time you sign in, the user all
$LocalPackagesFolder ="$env:LOCALAPPDATA\Packages"
$AADBrokerFolder = Get-ChildItem -Path $LocalPackagesFolder -Recurse -Include "Microsoft.AAD.BrokerPlugin_*";
$AADBrokerFolder = $AADBrokerFolder[0];
Get-ChildItem "$AADBrokerFolder\AC\TokenBroker\Accounts" | Remove-Item -Recurse -Force


################################################## clear oulook cache and recreate outlook profile  ###################################################
$offboard_confirm = "C:\offboarded_outlook_profile.txt"
$output = "Outlook Offboarding Already Done"
if(Test-Path $offboard_confirm)
{

}else{
    Remove-Item -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles\Outlook\*" -Recurse
    del C:\Users\$currentUserTruncated\AppData\Local\Microsoft\Outlook\*.ost
    del C:\Users\$currentUserTruncated\AppData\Local\Microsoft\Outlook\*.nst
    New-Item -Path HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Profiles -Name Outlook -force
    Write-Host $output | Out-File -FilePath $offboard_confirm
    }


# clear onedrive cache and rename old onedrive folders (could also choose to delete them, putting both options here)
$oneDriveCachePath = "$($profilePath)\AppData\Local\Microsoft\OneDrive"
$BaseFolderPath = "C:\Users\$currentUserTruncated\"
$OneDriveUserStoragePath = Get-ChildItem -Path $BaseFolderPath -Directory | Where-Object { $_.Name -like "Onedrive - *" }

#if(Test-Path $oneDrivePath)
#{
  Remove-Item -Path "$($oneDriveCachePath)\*" -Recurse -Force
  ###################### Uncomment below to move the old onedrive data to a hidden folder. Without this step, the old onedrive folder will still be visible to the user.#####
  #Rename-Item -Path $OneDriveUserStoragePath -NewName ".oldTenantOneDrive" 
  
#}

# sign out from windows
$shell = New-Object -ComObject Shell.Aplication
$ShellWindows = $shell.Windows()
foreach($Window in $ShellWindows)
{
  if($Window.Document.Url -eq "about:SignOut")
  {
    $Window.Quit()
  }
}

#log off to complete sign-out
shutdown.exe /l /f