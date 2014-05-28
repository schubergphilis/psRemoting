#psRemoting*
A collection of Powershell functions

####To activate:####
Beginning in Windows PowerShell 3.0, installed modules are automatically imported to the session when you use any commands or
providers in the module. However, you can still use the Import-Module command to import the psRemoting module

####Description:####
This is a collection (ahummm) of what I consider to be useful Powershell Remoting functions. The collection might grow over time with new functions.

####Function Overview####
Following functions have been released;

######Copy-RemoteFile######
A PowerShell function which copies a file from/to a remote server using PSRemote sessions. The remote session(s) need to be
created in advance! If no PSRemote session exists for the remote source or destination, an error message will be displayed
and the function will terminate. If both source and destination are local, a local Copy-Item command will be used.

Example:
  New-PSSession -Computer SRC .......
  New-PSSession -Computer DST .......
  Copy-RemoteFile \\SRC\C:\Tmp\Source.File \\DST\C:\Tmp\Destination.File [-Verbose] [-Check] [-Force]

Beware: The syntax resembles an UNC path but is not quit the same.

The computer names used when creating the session(s) must exactly match the names used with Copy-RemoteFile!
See EXAMPLES and the Examples folder for additional examples and information



Kind regards,
Hans van Veen