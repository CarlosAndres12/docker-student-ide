function New-CommandFake {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string]$LogPath,
        [int]$ExitCode = 0,
        [string]$Output = ""
    )

    if ($IsWindows) {
        $commandPath = Join-Path $Directory "$Name.cmd"
        $script = @"
@echo off
>>"$LogPath" echo $Name %*
if not "$Output"=="" echo $Output
exit /b $ExitCode
"@
        Set-Content -Path $commandPath -Value $script -Encoding ASCII
    } else {
        $commandPath = Join-Path $Directory $Name
        $quotedLog = $LogPath -replace "'", "'\''"
        $script = @"
#!/bin/sh
printf '%s %s\n' '$Name' "\$*" >> '$quotedLog'
[ -n '$Output' ] && printf '%s\n' '$Output'
exit $ExitCode
"@
        Set-Content -Path $commandPath -Value $script -Encoding ASCII
        if (Test-Path $commandPath) {
            & chmod +x $commandPath
        }
    }

    $commandPath
}
