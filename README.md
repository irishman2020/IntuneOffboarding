Warning! THis is a rough Draft of the script. More edits to come.

Purpose:
When a device is AD joined and Intune managed (but not hybrid) and the device is removed from the tenant, the account is left in Outlook, Onedrive, and Teams asking the user to sign back in.
To clear this, you can manually click the "sign out", but there aren't many resources on how to automate this. This script is to potentially fill in that gap.

Before running the script, remove the device from the current tenant by deleting the device and revoking the tokens. 
Then the script must be run at the system level (for testing, download pstools and use psexec - 'C:\PSTools\Psexec.exe -s -i powershell'). 

Items still needing to be added/fixed:
* Remove old OneDrive data option
* Recreate base Outlook profile so it is like it's a fresh install
