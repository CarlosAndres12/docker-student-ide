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
    #
    # On Windows the bootstrap rebuilds $env:Path from the registry, which
    # would drop the PATH fakes injected by the caller, and the machine PATH
    # precedes the user PATH so real System32 binaries (wsl.exe,
    # powershell.exe) would shadow the fakes. Replace the machine PATH with
    # the original snapshot plus this driver's fake directory so tests stay
    # isolated from each other's accumulated fakes. The VM guest is a
    # disposable overlay, so the mutation is intentionally not restored
    # (exit inside the flow prevents finally based cleanup anyway).
    $preamble = @(
        '$ErrorActionPreference = "Continue"',
        '$fakeDir = $env:FAKE_DIR',
        'if ($fakeDir) {',
        '    $winHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT',
        '    if ($winHost -and $env:ORIGINAL_MACHINE_PATH) {',
        '        [Environment]::SetEnvironmentVariable("Path", "$fakeDir;$env:ORIGINAL_MACHINE_PATH", "Machine")',
        '    }',
        '}',
        ". '$ScriptPath'"
    )
    $driverPath = Join-Path $Directory 'driver.ps1'
    Set-Content -Path $driverPath -Value (@($preamble) + @($Body) -join [Environment]::NewLine) -Encoding ASCII
    $driverPath
}
