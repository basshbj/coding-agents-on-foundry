[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Prompt = 'Reply with exactly MODEL_TEST_OK and a number between 1 - 10. Do not use tools or read files.',

    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Get-Command codex -ErrorAction Stop | Out-Null
$runTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path $PSScriptRoot "output_$runTimestamp"
}
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$models = [ordered]@{
    'gpt-6.1-sol' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-6.1-terra' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-6-astra' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-6-sol' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-6-luna' = @('low', 'medium', 'high', 'xhigh', 'max')
    'gpt-5.6-sol' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-5.6-terra' = @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')
    'gpt-5.6-luna' = @('low', 'medium', 'high', 'xhigh', 'max')
    'gpt-5.5' = @('low', 'medium', 'high', 'xhigh')
}

$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-model-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workingDirectory | Out-Null
$results = @()

try {
    foreach ($model in $models.Keys) {
        foreach ($effort in $models[$model]) {
            $answerPath = Join-Path $OutputDirectory "$model-$effort.txt"
            if (Test-Path -LiteralPath $answerPath) {
                Remove-Item -LiteralPath $answerPath
            }

            Write-Host "Testing $model ($effort)"
            & codex exec --model $model -c "model_reasoning_effort=$effort" `
                --sandbox read-only --skip-git-repo-check --ephemeral `
                --cd $workingDirectory --output-last-message $answerPath $Prompt | Out-Host
            $exitCode = $LASTEXITCODE
            $passed = $exitCode -eq 0 -and
                (Test-Path -LiteralPath $answerPath) -and
                -not [string]::IsNullOrWhiteSpace([System.IO.File]::ReadAllText($answerPath))

            if (-not $passed) {
                Write-Warning "$model ($effort) failed: exit code $exitCode or missing/empty answer."
            }

            $results += [pscustomobject]@{
                Model = $model
                ReasoningEffort = $effort
                ExitCode = $exitCode
                Passed = $passed
                AnswerFile = $answerPath
            }
        }
    }
}
finally {
    Remove-Item -LiteralPath $workingDirectory
}

$summaryPath = Join-Path $OutputDirectory "results_$runTimestamp.csv"
$results | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$results | Format-Table Model, ReasoningEffort, ExitCode, Passed -AutoSize
Write-Host "Results saved to $summaryPath"

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    throw "$($failed.Count) of $($results.Count) model tests failed. See $summaryPath."
}
