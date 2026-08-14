Import-Module Pester -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot "unit"
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = "Detailed"
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = "JUnitXml"
$resultPath = $env:PESTER_RESULTS_PATH
if (-not $resultPath) {
    $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) "docker-student-ide-windows-unit.xml"
}
$configuration.TestResult.OutputPath = $resultPath

$configuration
