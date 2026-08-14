function Invoke-BootstrapScenario {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [hashtable]$Environment = @{}
    )

    $previous = @{}
    foreach ($name in $Environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
    }

    try {
        $output = & pwsh.exe -NoProfile -NonInteractive -File $ScriptPath @Arguments 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    } finally {
        foreach ($name in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
    }
}
