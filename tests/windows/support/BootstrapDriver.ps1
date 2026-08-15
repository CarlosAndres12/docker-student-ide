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
    # would drop the PATH fakes injected by the caller. Registering the
    # fake directory in the USER registry PATH keeps it reachable after the
    # refresh. The VM guest is a disposable overlay, so the mutation is
    # intentionally not restored (exit inside the flow prevents finally
    # based cleanup anyway).
    $preamble = @(
        '$ErrorActionPreference = "Continue"',
        '$fakeDir = $env:FAKE_DIR',
        'if ($fakeDir) {',
        '    $winHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT',
        '    if ($winHost) {',
        '        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")',
        '        if (-not $userPath -or ($userPath -notlike "*$fakeDir*")) {',
        '            [Environment]::SetEnvironmentVariable("Path", "$fakeDir;$userPath", "User")',
        '        }',
        '    }',
        '}',
        ". '$ScriptPath'"
    )
    $driverPath = Join-Path $Directory 'driver.ps1'
    Set-Content -Path $driverPath -Value (@($preamble) + @($Body) -join [Environment]::NewLine) -Encoding ASCII
    $driverPath
}
