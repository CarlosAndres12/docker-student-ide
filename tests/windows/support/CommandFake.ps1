function New-CommandFake {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string]$LogPath,
        [int]$ExitCode = 0,
        [string]$Output = "",
        [string]$ExtraScript = ""
    )

    # Windows PowerShell 5.1 has no $IsWindows; use the platform check.
    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    if ($isWindowsHost) {
        $commandPath = Join-Path $Directory "$Name.cmd"
        $script = @"
@echo off
>>"$LogPath" echo $Name %*
if not "$Output"=="" echo $Output
$ExtraScript
exit /b $ExitCode
"@
        Set-Content -Path $commandPath -Value $script -Encoding ASCII
    } else {
        $commandPath = Join-Path $Directory $Name
        $quotedLog = $LogPath -replace "'", "'\''"
        $script = @"
#!/bin/sh
printf '%s %s\n' '$Name' "`$*" >> '$quotedLog'
[ -n '$Output' ] && printf '%s\n' '$Output'
$ExtraScript
exit $ExitCode
"@
        Set-Content -Path $commandPath -Value $script -Encoding ASCII
        if (Test-Path $commandPath) {
            & chmod +x $commandPath
        }
    }

    $commandPath
}
