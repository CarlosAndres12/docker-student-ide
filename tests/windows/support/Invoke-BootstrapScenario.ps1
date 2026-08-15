function Invoke-BootstrapScenario {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [hashtable]$Environment = @{},
        [string[]]$PrependPath = @(),
        [string[]]$AdditionalArgs = @()
    )

    $previous = @{}
    foreach ($name in $Environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
    }

    # Windows PowerShell 5.1 has no $IsWindows; use the platform check.
    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

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
        $launcher = if ($isWindowsHost) {
            if (Get-Command "pwsh.exe" -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
        } else { "pwsh" }
        # Bypass is the default so generated drivers can Import-Module Pester
        # even under the Windows Restricted default policy. Tests that need a
        # specific policy (I-04) override AdditionalArgs explicitly.
        $launcherArgs = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass") + @($AdditionalArgs)
        $output = & $launcher @launcherArgs -File $ScriptPath @Arguments 2>&1
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
