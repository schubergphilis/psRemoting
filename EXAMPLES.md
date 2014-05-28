##Copy-RemoteFile Examples##
This file shows you some of the possibilities of Copy-RemoteFile.

####Create the required credential objects####
PS C:\> $srcCred = Get-Credential 'SRC_Account'

Windows PowerShell Credential Request
Enter your credentials.
Password for user 'SRC_Account': ************

PS C:\> $dstCred = Get-Credential 'DST_Account'

Windows PowerShell Credential Request
Enter your credentials.
Password for user 'DST_Account': ***********


####Create the remote sessions using the created credential objects####
PS C:\> nsn -ComputerName SRC [-UseSSL] -Credential $srcCred

 Id Name            ComputerName    State         ConfigurationName     Availability
 -- ----            ------------    -----         -----------------     ------------
  1 Session1        SRC             Opened        Microsoft.PowerShell     Available


PS C:\> nsn -ComputerName DST [-UseSSL] -Credential $dstCred

 Id Name            ComputerName    State         ConfigurationName     Availability
 -- ----            ------------    -----         -----------------     ------------
  3 Session3        DST             Opened        Microsoft.PowerShell     Available


####Copy the remote source file to the remote destination and verify it when ready####
PS C:\> Copy-RemoteFile \\SRC\C:\Tmp\Source.File \\DST\C:\Tmp\Destination.File -Verbose -Check
VERBOSE: Verifying SRC for source file: C:\Tmp\Source.File
VERBOSE: Verifying DST for destination: C:\Tmp\Destination.File
VERBOSE: Verifying destination path on DST
VERBOSE: Verifying available free space at destination, required: 80358961 bytes
VERBOSE: Remote Copy started at: 09:46:28
VERBOSE: Sending 73053601 bytes in 1 iterations, using 536870912 bytes/iteration
VERBOSE:  - Sending 73053601 bytes - iteration #1
VERBOSE:            finished at: 09:46:41
VERBOSE:               duration: 12.1993564 sec.
VERBOSE:                  speed: 5988316 bytes/sec.
VERBOSE: Verifying checksum of copied file (can take some time...)
VERBOSE: Source checksum     : 97C5B62AB27C63765DDFBF34E868972B56CD68F76B994C95AC6D02CF19070D03
VERBOSE: Destination checksum: 97C5B62AB27C63765DDFBF34E868972B56CD68F76B994C95AC6D02CF19070D03
PS C:\>


######Problem 1. Source file does not exist######
PS C:\> Copy-RemoteFile \\SRC\C:\Tmp\Source.File-nx \\DST\C:\Tmp\Destination.File -Verbose -Check
VERBOSE: Verifying SRC for source file: C:\Tmp\Source.File-nx
Copy-RemoteFile : File C:\Tmp\Source.File-nx not found
At line:1 char:1
+ Copy-RemoteFile \\SRC\C:\Tmp\Source.File-nx \\DST\C:\Tm ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : ObjectNotFound: (:) [Write-Error], FileNotFound
    + FullyQualifiedErrorId : FileNotFound,Copy-RemoteFile


######Problem 2. Destination file already exists######
PS C:\> Copy-RemoteFile \\SRC\C:\Tmp\Source.File \\DST\C:\Tmp\Destination.File -Verbose -Check
VERBOSE: Verifying SRC for source file: C:\Tmp\Source.File
VERBOSE: Verifying DST for destination: C:\Tmp\Destination.File
Copy-RemoteFile : File C:\Tmp\Destination.File already exists
At line:1 char:1
+ Copy-RemoteFile \\SRC\C:\Tmp\Source.File \\DST\C:\Tmp\P ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : WriteError: (:) [Write-Error], FileAlreadyExists
    + FullyQualifiedErrorId : FileAlreadyExists,Copy-RemoteFile
