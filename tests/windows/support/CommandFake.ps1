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

    $commandPath = Join-Path $Directory "$Name.cmd"
    $script = @"
@echo off
if not "$Output"=="" echo $Output
exit /b $ExitCode
"@
    Set-Content -Path $commandPath -Value $script -Encoding ASCII
    $commandPath
}
