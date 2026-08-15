BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $installScript = Join-Path $repositoryRoot "scripts/install-native.ps1"
    $originalMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/CommandFake.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/BootstrapDriver.ps1")
    . $installScript

    function New-FakeDir {
        param([string]$Root)
        $dir = Join-Path $Root "fakes"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dir
    }

    function Invoke-NativeInstallerScenario {
        param(
            [string]$Workspace,
            [string]$Fakes,
            [string[]]$DriverBody,
            [hashtable]$ExtraEnvironment = @{}
        )
        $driver = New-BootstrapDriver -ScriptPath $installScript -Directory $Workspace -Body $DriverBody
        $environment = @{
            DOCKER_STUDENT_IDE_NONINTERACTIVE = "1"
            TEST_WORKSPACE = $Workspace
            FAKE_DIR = $Fakes
            ORIGINAL_MACHINE_PATH = $originalMachinePath
        }
        foreach ($key in $ExtraEnvironment.Keys) {
            $environment[$key] = $ExtraEnvironment[$key]
        }
        Invoke-BootstrapScenario -ScriptPath $driver -PrependPath @($Fakes) -Environment $environment
    }
}

Describe "NI-01 download and run from an empty directory" -Tag Unit {
    It "downloads the ZIP and runs setup-windows.ps1 with execution-policy bypass" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $webLog = Join-Path $ws.Path "web.log"
            $childLog = Join-Path $ws.Path "child.log"
            $null = New-CommandFake -Name "powershell.exe" -Directory $fakes -LogPath $childLog -ExitCode 0

            $result = Invoke-NativeInstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Invoke-WebRequest {'
                '    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)'
                '    Add-Content -Path $env:WEB_LOG -Value $Uri'
                '    Set-Content -Path $OutFile -Value "fakezip"'
                '}'
                'function Expand-Archive {'
                '    param([string]$Path, [string]$DestinationPath, [switch]$Force)'
                '    $dir = Join-Path $DestinationPath "docker-student-ide-main"'
                '    New-Item -ItemType Directory -Path $dir -Force | Out-Null'
                '    Set-Content -Path (Join-Path $dir "setup-windows.ps1") -Value "# fake"'
                '    Set-Content -Path (Join-Path $dir "requirements-windows.txt") -Value "# fake"'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-NativeInstaller'
                'exit $code'
            ) -ExtraEnvironment @{ WEB_LOG = $webLog }

            $result.ExitCode | Should -Be 0
            (Get-Content $webLog -Raw) | Should -Match "archive/refs/heads/main\.zip"
            (Get-Content $childLog -Raw) | Should -Match "-NoProfile -ExecutionPolicy Bypass -File"
            (Get-Content $childLog -Raw) | Should -Match "setup-windows\.ps1"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "NI-02 already in repository" -Tag Unit {
    It "skips the download and invokes the child with execution-policy bypass" {
        $ws = New-BootstrapTestWorkspace
        try {
            Set-Content -Path (Join-Path $ws.Path "setup-windows.ps1") -Value "# fixture"
            Set-Content -Path (Join-Path $ws.Path "requirements-windows.txt") -Value "# fixture"

            $fakes = New-FakeDir $ws.Path
            $webLog = Join-Path $ws.Path "web.log"
            $childLog = Join-Path $ws.Path "child.log"
            $null = New-CommandFake -Name "powershell.exe" -Directory $fakes -LogPath $childLog -ExitCode 0

            $result = Invoke-NativeInstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Invoke-WebRequest {'
                '    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)'
                '    Add-Content -Path $env:WEB_LOG -Value $Uri'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-NativeInstaller'
                'exit $code'
            ) -ExtraEnvironment @{ WEB_LOG = $webLog }

            $result.ExitCode | Should -Be 0
            Test-Path $webLog | Should -BeFalse
            (Get-Content $childLog -Raw) | Should -Match "-NoProfile -ExecutionPolicy Bypass -File"
            (Get-Content $childLog -Raw) | Should -Match "setup-windows\.ps1"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "NI-03 download failure" -Tag Unit {
    It "fails with actionable guidance when the download cannot complete" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path

            $result = Invoke-NativeInstallerScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Invoke-WebRequest {'
                '    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)'
                '    throw "network error"'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-NativeInstaller'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match "No se pudo descargar"
        } finally {
            & $ws.Cleanup
        }
    }
}
