[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$javaCommand = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCommand) {
    throw 'Java is required for the Groovy syntax check. CI installs the Jenkins-compatible Java runtime before this step.'
}

$groovyVersion = '2.4.21'
$groovySha256 = 'DE65260CF2070442E99882F2F3D72E7531725C1E6A257446CC0CEA525C607BD0'
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$jarPath = Join-Path $tempRoot "jenkins-groovy-all-$groovyVersion.jar"
$downloadPath = Join-Path $tempRoot ("jenkins-groovy-all-$groovyVersion." + [guid]::NewGuid().ToString('N') + '.tmp')
$jarUri = "https://repo.maven.apache.org/maven2/org/codehaus/groovy/groovy-all/$groovyVersion/groovy-all-$groovyVersion.jar"

try {
    if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf)) {
        Invoke-WebRequest -Uri $jarUri -OutFile $downloadPath
        $downloadHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
        if ($downloadHash -ne $groovySha256) {
            throw 'Downloaded Groovy artifact did not match the pinned SHA-256.'
        }
        Move-Item -LiteralPath $downloadPath -Destination $jarPath
    }

    $jarHash = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash
    if ($jarHash -ne $groovySha256) {
        throw 'Cached Groovy artifact did not match the pinned SHA-256.'
    }

    $pipelinePaths = @(
        'casc/jobs.groovy',
        'casc/pipelines/repository-pilot.groovy',
        'casc/pipelines/secondary-repository.groovy',
        'casc/pipelines/e2e.groovy',
        'casc/pipelines/test-platform.groovy'
    ) | ForEach-Object { Join-Path $repositoryRoot $_ }

    & $javaCommand.Source -cp $jarPath groovy.ui.GroovyMain (Join-Path $PSScriptRoot 'verify-groovy-syntax.groovy') @pipelinePaths
    if ($LASTEXITCODE -ne 0) {
        throw "Jenkins-pinned Groovy syntax validation failed with exit code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $downloadPath) {
        Remove-Item -LiteralPath $downloadPath -Force
    }
}
