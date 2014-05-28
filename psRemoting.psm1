# psRemoting - a collection of PowerShell functions using/enhancing the Windows PowerShell remoting infrastructure.
#
#         Copyright 2014, Hans L.M. van Veen
#         
#         Licensed under the Apache License, Version 2.0 (the "License");
#         you may not use this file except in compliance with the License.
#         You may obtain a copy of the License at
#         
#             http://www.apache.org/licenses/LICENSE-2.0
#         
#         Unless required by applicable law or agreed to in writing, software
#         distributed under the License is distributed on an "AS IS" BASIS,
#         WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#         See the License for the specific language governing permissions and
#         limitations under the License.
#
############################################################################################################################
#  Copy-RemoteFile
#    Copies a file from a (remote) source host to a (remote) destination host
############################################################################################################################
function Copy-RemoteFile {
<# 
 .Synopsis
  Copies a file from a (remote) source host to a (remote) destination host.

 .Description
  This function copies a single(!) file from/to a remote server using PSRemote sessions. The remote session(s) need to be
  created in advance! If no PSRemote session exists for the remote source or destination, an error message will be displayed
  and the function will terminate. If both source and destination are local, a local Copy-Item command will be used.

 .Parameter Source
  The source file to copy. The file will be checked for existence.
  
  Format: [\\Server\]Drive:\Folder\Filename
  
  If the filename is preceded by '\\Server[\x:\[...]]' the source file is assumed to be on a remote server for which a PSRemote session is required.

 .Parameter Destination
  The destination file to create. 'Missing' parts will be replaced with their source file equivalent.
  
  Format: [\\Server\]Drive:\Folder\Filename
  
  If the filename is preceded by '\\Server\' the destination is assumed to be on a remote server for which a PSRemote session is required.

 .Parameter Check
  If -Check is specified the copied file will be checksum compared to the original (can take some time with large files!)

 .Parameter Force
  When specified;
  - an existing destination file will be overwritten.
  - a non-existing destination folder will be created.
  
  .Example
  # Copy a file from a remote source to a remote destination.
  PS C:\> nsn -ComputerName SRC [-UseSSL] -Credential $srcCred

  Id Name            ComputerName    State         ConfigurationName     Availability
  -- ----            ------------    -----         -----------------     ------------
   1 Session1        SRC             Opened        Microsoft.PowerShell     Available

  PS C:\> nsn -ComputerName DST [-UseSSL] -Credential $dstCred

  Id Name            ComputerName    State         ConfigurationName     Availability
  -- ----            ------------    -----         -----------------     ------------
   3 Session3        DST             Opened        Microsoft.PowerShell     Available

  PS C:\> Copy-RemoteFile \\SRC\C:\Tmp\Source.File \\DST\C:\Tmp\Destination.File -Verbose -Check
  VERBOSE: Verifying SRC for source file: C:\Tmp\Source.File
  VERBOSE: Verifying DST for destination: C:\Tmp\Destination.File
  ...........
  
  
  .Example
   # Copy a file from a remote source to a remote destination. Source file will be copied to: E:\NEWDIR\File.Ext on server UVWXYZ

   Copy-RemoteFile \\ABCDEF\C:\DIR\File.Ext  \\UVWXYZ\E:\NEWDIR

 .Example
   # Copy a file from a remote source to a local destination.

   Copy-RemoteFile \\ABCDEF\C:\DIR\File.Ext  E:\NEWDIR

 .Example
   # Copy a file from a remote source to a remote destination. Source file will be copied to: C:\DIR\File.Ext on server UVWXYZ

   Copy-RemoteFile \\ABCDEF\C:\DIR\File.Ext  \\UVWXYZ
#>
############################################################################################################################
param([Parameter(Mandatory=$true, Position = 0)][ValidateNotNullOrEmpty()][string]$Source,
      [Parameter(Mandatory=$true, Position = 1)][ValidateNotNullOrEmpty()][string]$Destination,
      [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][switch]$Check,
      [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][switch]$Force)
    ########################################################################################################################
    #  Local variable definitions. The maximum amount of data a remote server can handle is defined by the
    #  $PSSessionOption.MaximumReceivedDataSizePerCommand setting Use max 25% of this space! If the variable
	#  returns 0 then use $PSSessionOption.MaximumReceivedObjectSize and if that fails use 128MB as value
    # ----------------------------------------------------------------------------------------------------------------------
    $sndSize = 5MB
    $maxSize = [Int]($PSSessionOption.MaximumReceivedDataSizePerCommand/4)
	if ($maxSize -eq 0) { $maxSize = [Int]($PSSessionOption.MaximumReceivedObjectSize/4) }
	if ($maxSize -eq 0) { $maxSize = 128MB }
    $srvRegex = "^\\\\(.*)\\([a-zA-Z]:\\.*?)$"
    # ======================================================================================================================
    #  Send File code - Used for both local and remote files!
    #    This code depends on session variables previously set!! (see comment ~ line 195)
    # ----------------------------------------------------------------------------------------------------------------------
    $CRFsndFile = {
        param($bytesToSend, $chunkSize)
    	while ($bytesToSend -gt 0)
    	{
            $sendBufferSize = [Math]::Min($bytesToSend,$chunkSize)
            $sendBuffer = New-Object byte[] $sendBufferSize
            $byteCnt = $srcFS.Read($sendBuffer,0,$sendBufferSize)
            Write-Output $([System.Convert]::ToBase64String($sendBuffer))
            $bytesToSend -= $chunkSize
            rv sendBuffer
        }
    }
    # ======================================================================================================================
    #  Receive File code - Used for both local and remote files!
    #    This code depends on session variables previously set!! (see comment ~ line 195)
    #    Trial and Error has shown that closing and re-opening the destination file every 7 chunks will
    #    prevent memory overruns, you can experiment yourself by altering "($partCnt%7 -ne 0)"
    # ----------------------------------------------------------------------------------------------------------------------
    $CRFrcvFile = {
        param($Chunk)
        $receiveBuffer = [System.Convert]::FromBase64String($Chunk)
        $dstFS.Write($receiveBuffer,0,$receiveBuffer.Length)
        if ($partCnt%7 -ne 0) { $partCnt += 1 }
        else { $dstFS.Close(); $dstFS = [System.IO.File]::Open($dstFile, [System.IO.FileMode]::Append) } 
        rv receiveBuffer
    }
    # ======================================================================================================================
    #  Get SHA256 hash code - Used for both local and remote files! (Copy of PS V4 Get-FileHash)
    # ----------------------------------------------------------------------------------------------------------------------
    $CRFgetFileHash = {
        param($File)
        $hasher = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")
        try
        {
            [system.io.stream]$stream = [System.IO.File]::OpenRead($File)
            [Byte[]]$computedHash = $hasher.ComputeHash($stream)
        }
        catch [Exception]
        {
            $errorMessage = [Microsoft.PowerShell.Commands.UtilityResources]::FileReadError -f $File, $_
            Write-Error -Message $errorMessage -Category ReadError -ErrorId "FileReadError" -TargetObject $File
            return
        }
        finally { if($stream) { $stream.Close() } }
        Write-Output $([BitConverter]::ToString($computedHash) -replace '-','')
    }
    # ======================================================================================================================
    # <<<<< MAIN >>>>>                                   Start the magic!                                   <<<<< MAIN >>>>>
    # ======================================================================================================================
    #  Check source and destination, If both are not remote we perform a local file copy and quit.
    #  BEWARE: If source or destination is local use "StartJob" instead of "Invoke-Command -AsJob"
    #          This last command does not work on a local computer!!!!
    # ----------------------------------------------------------------------------------------------------------------------
    $CRFsrcHost = "$($env:ComputerName)";  $CRFremoteSrc = $Source -match $srvRegex;
    if ($CRFremoteSrc) { $CRFsrcHost = $Matches[1]; $Source = $Matches[2] }
    $CRFdstHost = "$($env:ComputerName)"; $CRFremoteDst = $Destination -match $srvRegex;
    if ($CRFremoteDst) { $CRFdstHost = $Matches[1]; $Destination = $Matches[2] }
    if (!$CRFremoteSrc -and !$CRFremoteDst) { Copy-Item "$Source" "$Destination" ; Exit }
    # ----------------------------------------------------------------------------------------------------------------------
    #  Check the source server and if it is remote check for a PSSession to that server
    #  Verify the source file existence before continuing. (quit when non-existing)
    # ----------------------------------------------------------------------------------------------------------------------
    $iexCmd = "[IO.FileInfo]`"$Source`""
    if ($CRFremoteSrc)
    {
        $CRFsrcSession = Get-PSSession|?{ $_.ComputerName -eq $CRFsrcHost}
        if ($CRFsrcSession.State -ne "Opened") { throw "No open PSRemote session found for source $CRFsrcHost" }
        $iexCmd = "icm -Session `$CRFsrcSession {[IO.FileInfo]`"$Source`"}"
    }
    Write-Verbose "Verifying $CRFsrcHost for source file: $Source"
    $CRFsrcInfo = iex $iexCmd
    if (!$CRFsrcInfo.Exists)
    {
        $errorMsg = "File $($CRFsrcInfo.FullName) not found"
        $exception = New-Object System.Management.Automation.ItemNotFoundException $errorMsg
        $errorID = 'FileNotFound'
        $errorCategory = [Management.Automation.ErrorCategory]::ObjectNotFound
        Write-Error -Message $errorMsg -Category $errorCategory -CategoryReason FileNotFound -CategoryActivity Copy-RemoteFile -ErrorID $errorID
        return
    }
    $CRFsrcFile = $CRFsrcInfo.FullName
    $CRFsrcPath = $CRFsrcInfo.DirectoryName
    $CRFsrcName = $CRFsrcInfo.Name
    # ----------------------------------------------------------------------------------------------------------------------
    #  Check the destination server and if it is remote check for a PSSession to that server. When OK check the specified
    #  destination file spec and if needed use the source file spec to fill in empty parts it
    # ----------------------------------------------------------------------------------------------------------------------
    if ($Destination.Length -eq 0) { $Destination = $CRFdstFile = $CRFsrcFile }
    $iexCmd = "[IO.FileInfo]`"$Destination`""
    if ($CRFremoteDst)
    {
        $CRFdstSession = Get-PSSession|?{ $_.ComputerName -eq $CRFdstHost}
        if ($CRFdstSession.State -ne "Opened") { throw "No open PSRemote session found for destination $CRFdstHost" }
        $iexCmd = "icm -Session `$CRFdstSession {[IO.FileInfo]`"$Destination`"}"
    }
    # ----------------------------------------------------------------------------------------------------------------------
    #  Check whether destination file already exists. Is so and -Force has not been specified quit the action
    # ----------------------------------------------------------------------------------------------------------------------
    Write-Verbose "Verifying $CRFdstHost for destination: $Destination"
    $CRFdstInfo = iex $iexCmd
    if (($CRFdstInfo.Exists) -and !$Force)
    {
        $errorMsg = "File $($CRFdstInfo.FullName) already exists"
        $exception = New-Object System.Management.Automation.ItemNotFoundException $errorMsg
        $errorID = 'FileAlreadyExists'
        $errorCategory = [Management.Automation.ErrorCategory]::WriteError
        Write-Error -Message $errorMsg -Category $errorCategory -CategoryReason FileAlreadyExists -CategoryActivity Copy-RemoteFile -ErrorID $errorID
        return
    }
    # ----------------------------------------------------------------------------------------------------------------------
    #  
    # ----------------------------------------------------------------------------------------------------------------------
    if ($CRFdstInfo.Attributes.ToString().Contains("Directory"))                  # Destination is directory spec
    {
        $CRFdstPath = $Destination
        $CRFdstName = $CRFsrcInfo.Name
        $Destination = $CRFdstFile = "$CRFdstPath\$CRFdstName"
    }
    else
    {
        $CRFdstFile = $CRFdstInfo.FullName
        $CRFdstPath = $CRFdstInfo.DirectoryName
        $CRFdstName = $CRFdstInfo.Name
    }
    # ----------------------------------------------------------------------------------------------------------------------
    #  Check whether the destination folder exist. If not and -Force has been specified create the destination folder
    # ----------------------------------------------------------------------------------------------------------------------
    $iexCmd = "[IO.DirectoryInfo]`"$CRFdstPath`""
    if ($CRFremoteDst) { $iexCmd = "icm -Session `$CRFdstSession {[IO.DirectoryInfo]`"$CRFdstPath`"}" }
    Write-Verbose "Verifying destination path on $CRFdstHost"
    $CRFdstDirInfo = iex $iexCmd
    if (!$CRFdstDirInfo.Exists)
    {
        if (!$Force) { throw "Destination path $CRFdstPath does not exist" }
        if (!$CRFremoteDst) { [void](ni "$($CRFdstDirInfo.FullName)" -ItemType Directory -Force) }
        else { icm -Session $CRFdstSession { param($dstPath); ni "$dstPath" -ItemType Directory -Force } -Args $CRFdstDirInfo.FullName }
    }
    # ----------------------------------------------------------------------------------------------------------------------
    #  If source and destination host are identical and remote: perform a remote 'local' copy and quit.
    # ----------------------------------------------------------------------------------------------------------------------
    if ($CRFremoteDst -and ($CRFsrcHost -eq $CRFdstHost))
    {
        icm -Session $CRFsrcSession { Copy-Item "$Source" "$Destination" }
        return
    }
    # ----------------------------------------------------------------------------------------------------------------------
    #  Now verify whether there is sufficient storage space at the destination (to be save; use 95% of available)
    # ----------------------------------------------------------------------------------------------------------------------
    $xfrBytes = $maxBytes = $CRFsrcInfo.Length
    Write-Verbose "Verifying available free space at destination, required: $([Int64](1.1 * $maxBytes)) bytes"
    if (!$CRFremoteDst) { $availBytes = (iex "icm {([IO.DriveInfo]`"$CRFdstPath`").AvailableFreeSpace}") }
    else { $availBytes = (iex "icm -Session `$CRFdstSession {([IO.DriveInfo]`"$CRFdstPath`").AvailableFreeSpace}") }
    $avlBytes = [Int64](0.95 * $availBytes)
    if ($maxBytes -ge $avlBytes) { throw "Not enough free space at destination, required $([Int64](1.1 * $maxBytes)) bytes" }
    # ======================================================================================================================
    #   Open the destination file so we can start the transfer, fetch the source file and pass the blocks to the
    #   destination, and close the source & destination files when ready. The variables used and their values will be
    #   available to every other command invoked in that session
    # ----------------------------------------------------------------------------------------------------------------------
    if (!$CRFremoteSrc) { if ($srcFS.CanRead) {$srcFS.Close()};  $srcFS = [System.IO.File]::OpenRead($CRFsrcFile) }
    else { icm -Session $CRFsrcSession { param($srcFile); if ($srcFS.CanRead) {$srcFS.Close()}; $srcFS = [System.IO.File]::OpenRead($srcFile) } -Args "$CRFsrcFile" }
    if (!$CRFremoteDst) { if ($dstFS.CanWrite) {$dstFS.Close()}; $dstFS = [System.IO.File]::Open($CRFdstFile, [System.IO.FileMode]::Create); $partCnt = 0 }
    else { icm -Session $CRFdstSession { param($dstFile); if ($dstFS.CanWrite) {$dstFS.Close()}; $dstFS = [System.IO.File]::Open($dstFile, [System.IO.FileMode]::Create); $partCnt = 0 } -Args "$CRFdstFile" }
    # ----------------------------------------------------------------------------------------------------------------------
    #   When using -Verbose do not flood the display with messages. Use an iteration depending on the file size
    # ----------------------------------------------------------------------------------------------------------------------
    $noIterations = [int]($maxBytes/$maxSize+0.49); if ($noIterations -eq 0) { $noIterations = 1 }
    $iterBlockSize = $iterCnt = 1
    if ($noIterations -gt 10)       { $iterBlockSize = 5 }
    elseif ($noIterations -gt 100)  { $iterBlockSize = 10 }
    elseif ($noIterations -gt 1000) { $iterBlockSize = 100 }
    # ----------------------------------------------------------------------------------------------------------------------
    #   The source and destination file are ready for copying content. Lets do so....... 
    # ----------------------------------------------------------------------------------------------------------------------
    $crfStart = Get-Date
    Write-Verbose "Remote Copy started at: $(Get-Date($crfStart) -f "HH:mm:ss")"
    Write-Verbose "Sending $maxBytes bytes in $noIterations iterations, using $maxSize bytes/iteration"
    while ($maxBytes -gt 0)
    {
        $sndBytes = [Math]::Min($maxBytes, $maxSize); $maxBytes -= $maxSize;
        if ($iterCnt%$iterBlockSize -eq 0) { Write-Verbose " - Sending $sndBytes bytes - iteration #$iterCnt" }; $iterCnt += 1
        if (!$CRFremoteSrc)  { icm $CRFsndFile -Args $sndBytes,$sndSize | %{ icm -Session $CRFdstSession $CRFrcvFile -Args $_ } }
        elseif (!$CRFremoteDst) { icm -Session $CRFsrcSession $CRFsndFile -Args $sndBytes,$sndSize | %{ icm $CRFrcvFile -Args $_ } }
        else { icm -Session $CRFsrcSession $CRFsndFile -Args $sndBytes,$sndSize | %{ icm -Session $CRFdstSession $CRFrcvFile -Args $_ } }
    }
    if (!$CRFremoteSrc) { $srcFS.Close() }
    else { icm -Session $CRFsrcSession { $srcFS.Close() } }
    if (!$CRFremoteDst) { $dstFS.Close() }
    else { icm -Session $CRFdstSession { $dstFS.Close() } }
    $crfEnd = Get-Date; $crfElapsed = ($crfEnd - $crfStart).TotalSeconds; [Int]$bps = $xfrBytes/$crfElapsed
    Write-Verbose "           finished at: $(Get-Date($crfEnd) -f "HH:mm:ss")"
    Write-Verbose "              duration: $crfElapsed sec."
    Write-Verbose "                 speed: $bps bytes/sec."
    # ======================================================================================================================
    #  If requested perform a SHA256 hash check
    # ----------------------------------------------------------------------------------------------------------------------
    if ($Check)
    {
        Write-Verbose "Verifying checksum of copied file (can take some time...)"
        if (!$CRFremoteSrc) { $s_job = (Start-Job $CRFgetFileHash -Args "$CRFsrcFile") }
        else { $s_job = (icm -Session $CRFsrcSession $CRFgetFileHash -Args "$CRFsrcFile" -AsJob) }
        if (!$CRFremoteDst) { $d_job = (Start-Job $CRFgetFileHash -Args "$CRFdstFile") }
        else { $d_job = (icm -Session $CRFdstSession $CRFgetFileHash -Args "$CRFdstFile" -AsJob) }
        $a = Wait-Job $s_job; $sCS = Receive-Job $s_job; Remove-Job $s_job; Write-Verbose "Source checksum     : $sCS"
        $a = Wait-Job $d_job; $dCS = Receive-Job $d_job; Remove-Job $d_job; Write-Verbose "Destination checksum: $dCS"
        if ($sCS -ne $dCS)
        {
            if (!$CRFremoteDst) { ri -Literal "$CRFdstFile" -Force }
            else { iex "icm -Session `$CRFdstSession {ri -Literal `"$CRFdstFile`" -Force}" }
            Write-Error "Checksum does not match!! Destination file has been deleted"
        }
    }
}
# ==========================================================================================================================
#   End of Function: Copy-RemoteFile
# ==========================================================================================================================