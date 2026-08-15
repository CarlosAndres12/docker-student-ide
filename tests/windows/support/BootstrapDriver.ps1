function New-BootstrapDriver {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [Parameter(Mandatory)]
        [string]$Directory,
        [Parameter(Mandatory)]
        [string[]]$Body
    )

    # The driver runs WITHOUT Pester: function shadows (defined in Body)
    # take precedence over cmdlets, which keeps child-process exit codes
    # intact (Pester suppresses exit inside test blocks) and avoids the
    # slow Pester startup per child.
    $preamble = @(
        '$ErrorActionPreference = "Continue"',
        ". '$ScriptPath'"
    )
    $driverPath = Join-Path $Directory 'driver.ps1'
    Set-Content -Path $driverPath -Value (@($preamble) + @($Body) -join [Environment]::NewLine) -Encoding ASCII
    $driverPath
}
