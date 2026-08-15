BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $setupScript = Join-Path $repositoryRoot "setup-windows.ps1"
    $originalMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    . (Join-Path $repositoryRoot "tests/windows/support/TestWorkspace.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/CommandFake.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/Invoke-BootstrapScenario.ps1")
    . (Join-Path $repositoryRoot "tests/windows/support/BootstrapDriver.ps1")
    . $setupScript

    function New-FakeDir {
        param([string]$Root)
        $dir = Join-Path $Root "fakes"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dir
    }

    function Invoke-SetupScenario {
        param(
            [string]$Workspace,
            [string]$Fakes,
            [string[]]$DriverBody,
            [hashtable]$ExtraEnvironment = @{}
        )
        $driver = New-BootstrapDriver -ScriptPath $setupScript -Directory $Workspace -Body $DriverBody
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

Describe "N-02 winget prerequisite" -Tag Unit {
    It "fails fast with guidance when winget is missing" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "winget") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$code = Invoke-Setup'
                'exit $code'
            )

            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match "aka.ms/getwinget"
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "N-03 npm global installs" -Tag Unit {
    It "installs a pinned global package when the binary is missing" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $npmLog = Join-Path $ws.Path "npm.log"
            $null = New-CommandFake -Name "npm" -Directory $fakes -LogPath $npmLog -ExitCode 0

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "create-vite") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$null = Install-NpmGlobal -Package "create-vite@5.1.0" -Binary "create-vite"'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            (Get-Content $npmLog -Raw) | Should -Match "install -g create-vite@5\.1\.0"
        } finally {
            & $ws.Cleanup
        }
    }

    It "skips the install when the binary is already present" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $npmLog = Join-Path $ws.Path "npm.log"
            $null = New-CommandFake -Name "npm" -Directory $fakes -LogPath $npmLog -ExitCode 0

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "create-vite") { return [pscustomobject]@{ Name = "create-vite"; Source = "fake" } }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$null = Install-NpmGlobal -Package "create-vite@5.1.0" -Binary "create-vite"'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            Test-Path $npmLog | Should -BeFalse
        } finally {
            & $ws.Cleanup
        }
    }
}

Describe "N-04 Antigravity CLI install" -Tag Unit {
    It "uses the official installer and never the npm placeholder" {
        $script = Get-Content $setupScript -Raw
        $script | Should -Match "irm https://antigravity\.google/cli/install\.ps1"
        $script | Should -Not -Match "npm install -g antigravity"
        $script | Should -Match "antigravity-cli.*is a placeholder"
    }
}

Describe "N-05 VS Code settings merge" -Tag Unit {
    It "creates the settings file and merges without clobbering" {
        $path = Join-Path $TestDrive "Code\User\settings.json"
        Merge-JsonSettings -Path $path -Values @{ "terminal.integrated.allowChords" = $false }
        $first = Get-Content $path -Raw | ConvertFrom-Json
        $first.'terminal.integrated.allowChords' | Should -BeFalse

        Merge-JsonSettings -Path $path -Values @{ "terminal.integrated.sendKeybindingsToShell" = $true }
        $merged = Get-Content $path -Raw | ConvertFrom-Json
        $merged.'terminal.integrated.allowChords' | Should -BeFalse
        $merged.'terminal.integrated.sendKeybindingsToShell' | Should -BeTrue
    }

    It "is idempotent across a second run" {
        $path = Join-Path $TestDrive "repeat\settings.json"
        Merge-JsonSettings -Path $path -Values @{ "workbench.colorTheme" = "Dark" }
        $before = Get-Content $path -Raw
        Merge-JsonSettings -Path $path -Values @{ "workbench.colorTheme" = "Dark" }
        Get-Content $path -Raw | Should -Be $before
    }
}

Describe "N-06 VS Code extension harness" -Tag Unit {
    It "lists the full marketplace extension set including pylance and docker" {
        $script = Get-Content $setupScript -Raw
        $script | Should -Match "ms-python\.python"
        $script | Should -Match "ms-python\.vscode-pylance"
        $script | Should -Match "ms-azuretools\.vscode-docker"
        $script | Should -Match "ms-toolsai\.jupyter"
        $script | Should -Match "esbenp\.prettier-vscode"
        $script | Should -Match "Gruntfuggly\.todo-tree"
    }
}

Describe "N-07 version gating" -Tag Unit {
    It "reports Node major 0 when node is absent" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "node") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$m = Get-NodeMajorVersion'
                'Write-Host "MAJOR=$m"'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            ($result.Output -join "`n") | Should -Match "MAJOR=0"
        } finally {
            & $ws.Cleanup
        }
    }

    It "parses the major from an installed Node version" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $nodeLog = Join-Path $ws.Path "node.log"
            $null = New-CommandFake -Name "node" -Directory $fakes -LogPath $nodeLog -ExitCode 0 -Output "v22.23.1"

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$m = Get-NodeMajorVersion'
                'Write-Host "MAJOR=$m"'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            ($result.Output -join "`n") | Should -Match "MAJOR=22"
        } finally {
            & $ws.Cleanup
        }
    }

    It "resolves no launcher when neither py nor python is present" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'function Get-Command {'
                '    param([string]$Name, [string]$ErrorAction)'
                '    if ($Name -eq "py" -or $Name -eq "python") { return $null }'
                '    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters'
                '}'
                'Set-Location $env:TEST_WORKSPACE'
                '$r = Resolve-PythonLauncher'
                'Write-Host ("RESOLVED=" + ($null -eq $r))'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            ($result.Output -join "`n") | Should -Match "RESOLVED=True"
        } finally {
            & $ws.Cleanup
        }
    }

    It "resolves the py launcher when py -3.13 is available" {
        $ws = New-BootstrapTestWorkspace
        try {
            $fakes = New-FakeDir $ws.Path
            $pyLog = Join-Path $ws.Path "py.log"
            $null = New-CommandFake -Name "py" -Directory $fakes -LogPath $pyLog -ExitCode 0 -Output "Python 3.13.0"

            $result = Invoke-SetupScenario -Workspace $ws.Path -Fakes $fakes -DriverBody @(
                'Set-Location $env:TEST_WORKSPACE'
                '$r = Resolve-PythonLauncher'
                'Write-Host ("ARGS=" + ($r.Args -join ","))'
                'exit 0'
            )

            $result.ExitCode | Should -Be 0
            ($result.Output -join "`n") | Should -Match "ARGS=-3\.13"
        } finally {
            & $ws.Cleanup
        }
    }
}
