#Requires -Version 6.0

function Exec([string] $Title, [string] $Command, [string[]] $CommandArguments, [Switch] $SuppressOutput, [Switch] $ShowArguments) 
{
    $ErrorActionPreference = "Stop"
    try
    {
        Write-Host '====================================================================='
        Write-Host "Executing: $Title"
        if ($ShowCommand) { Write-Host "$Command $CommandArguments" }
        Write-Host '---------------------------------------------------------------------'
        
        $CommandOutput = & $Command $CommandArguments
        if (!$SuppressOutput) { Write-Host $CommandOutput }
        if ($LASTEXITCODE -ne 0)
        {
            throw "Command '$Command' failed with exit code '$LASTEXITCODE'. Command output: '$CommandOutput'"
        }

        Write-Host '---------------------------------------------------------------------'
        Write-Host "Executing: $Title... DONE!"
        Write-Host '====================================================================='
        return $CommandOutput
    }
    catch 
    {
        Write-Error "Command '$Command' failed."
        throw
    }
}