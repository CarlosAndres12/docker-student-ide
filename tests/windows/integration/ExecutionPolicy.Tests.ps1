BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
}

Describe "I-04 restricted execution policy" -Tag NativeWindows {
    It "runs the staged installer under a restricted policy via the one-liner path" {
        $ws = New-BootstrapTestWorkspace
        try {
            # Staged copy of the installer so the flow does not depend on the
            # network one-liner.
            $installCopy = Join-Path $ws.Path "install.ps1"
            Copy-Item (Join-Path $repositoryRoot "scripts/install.ps1") $installCopy

            # Stub start.ps1: a script file that a Restricted policy blocks
            # unless the installer's child-seam bypass applies.
            $startStub = Join-Path $ws.Path "start.ps1"
            Set-Content -Path $startStub -Value @'
Set-Content -Path $env:TEST_MARKER_PATH -Value "bypass-ok"
exit 0
'@ -Encoding ASCII

            # Negative control: under Restricted, running the stub as a file
            # must fail and must not write the marker.
            $controlMarker = Join-Path $ws.Path "marker-control.txt"
            $control = Invoke-BootstrapScenario -ScriptPath $startStub `
                -AdditionalArgs @("-ExecutionPolicy", "Restricted") `
                -Environment @{ TEST_MARKER_PATH = $controlMarker }
            Test-Path $controlMarker | Should -BeFalse
            $control.ExitCode | Should -Not -Be 0

            # Positive: the documented one-liner analog (Get-Content | iex)
            # under Restricted must reach the installer, which spawns the
            # real child powershell with -ExecutionPolicy Bypass.
            $marker = Join-Path $ws.Path "marker.txt"
            $command = "Set-Location '$($ws.Path)'; iex (Get-Content '$installCopy' -Raw)"
            $result = Invoke-BootstrapScenario `
                -AdditionalArgs @("-ExecutionPolicy", "Restricted") `
                -Environment @{ TEST_MARKER_PATH = $marker } `
                -Command $command

            $result.ExitCode | Should -Be 0
            Test-Path $marker | Should -BeTrue
            (Get-Content $marker -Raw) | Should -Be "bypass-ok"
            ($result.Output -join "`n") | Should -Not -Match "Password|secret|token"
        } finally {
            & $ws.Cleanup
        }
    }
}
