param(
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Resolve-Path (Join-Path $projectDir "..")
$projectFile = Join-Path $projectDir "LockdownReady.Windows\LockdownReady.Windows.csproj"
$outputDir = Join-Path $rootDir "LockdownReady.Windows"

$publishArgs = @(
    "publish"
    $projectFile
    "-c"
    "Release"
    "-r"
    "win-x64"
    "--nologo"
    "-o"
    $outputDir
)

if ($SelfContained) {
    $publishArgs += @(
        "--self-contained"
        "true"
        "-p:PublishSingleFile=true"
        "-p:PublishReadyToRun=true"
    )
} else {
    $publishArgs += @(
        "--self-contained"
        "false"
    )
}

Write-Host "Publishing Windows app..."
dotnet @publishArgs
Write-Host "Published to $outputDir"
