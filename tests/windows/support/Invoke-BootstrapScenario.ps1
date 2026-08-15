function Invoke-BootstrapScenario {
    param(
        [string]$ScriptPath = "",
        [string[]]$Arguments = @(),
        [hashtable]$Environment = @{},
        [string[]]$PrependPath = @(),
        [string[]]$AdditionalArgs = @(),
        [string]$Command = ""
    )

    $previous = @{}
    foreach ($name in $Environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
    }

    # Windows PowerShell 5.1 has no $IsWindows; use the platform check.
    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    # Resolve the engine's absolute path BEFORE the PATH is modified:
    # a fake powershell.exe on the prepended PATH must not swallow the
    # launcher spawn itself (it may only intercept the SUT's child calls).
    $launcherName = if ($isWindowsHost) {
        if (Get-Command "pwsh.exe" -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
    } else { "pwsh" }
    $launcherPath = (Get-Command $launcherName -ErrorAction Stop).Source

    $pathChanged = $false
    if ($PrependPath.Count -gt 0) {
        $pathChanged = $true
        # "PATH" (not "Path"): Linux is case-sensitive for env var names.
        $previousPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
        $separator = if ($isWindowsHost) { ";" } else { ":" }
        $newPath = (@($PrependPath) -join $separator) + $separator + $previousPath
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "Process")
    }

    try {
        # Bypass is the default so generated drivers can Import-Module Pester
        # even under the Windows Restricted default policy. Tests that need a
        # specific policy (I-04) override AdditionalArgs explicitly; the
        # last -ExecutionPolicy occurrence wins.
        $launcherArgs = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass") + @($AdditionalArgs)
        if ($Command) {
            $output = & $launcherPath @launcherArgs -Command $Command 2>&1
        } else {
            $output = & $launcherPath @launcherArgs -File $ScriptPath @Arguments 2>&1
        }
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    } finally {
        foreach ($name in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
        if ($pathChanged) {
            [Environment]::SetEnvironmentVariable("PATH", $previousPath, "Process")
        }
    }
}
