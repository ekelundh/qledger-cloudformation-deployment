#Requires -Version 6.0

# Quick and dirty script to get ECR and S3 bucket up.
# S3 bucket will be filled with CF templates needed to deploy QLedger

[CmdletBinding()]
param (
    [Parameter()]
    [string] $ECRName = 'qledger',

    [Parameter()]
    [string] $QLedgerGitRepositoryFullDirectoryPath,

    [Parameter()]
    [string] $AWSRegion,

    [Parameter()]
    [string] $AWSAccountId
)
begin
{
    $ErrorActionPreference = "Stop"
    [string] $rootDirectory = Split-Path (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent) -Parent
    [string] $commonScriptsPath = Join-Path $rootDirectory 'scripts' 'common.ps1'
    . $commonScriptsPath

    if ([string]::IsNullOrWhitespace($ECRName))
    {
        throw "ECRName must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($QLedgerGitRepositoryFullDirectoryPath))
    {
        throw "QLedgerGitRepositoryFullDirectoryPath must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($AWSRegion))
    {
        throw "AWSRegion must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($AWSAccountId))
    {
        throw "AWSAccountId must be non-empty."
    }

    [string] $awsCliCommand = 'aws'
    try
    {
        Get-Command $awsCliCommand | Out-Null
    }
    catch
    {
        throw "Failed to find AWS CLI. Please make sure the AWS CLI is installed. AWS CLI command used: '$awsCliCommand'."
    }

    [string] $dockerCliCommand = 'docker'
    try
    {
        Get-Command $dockerCliCommand | Out-Null
    }
    catch
    {
        throw "Failed to find Docker CLI. Please make sure that Docker is installed. Docker CLI command used: '$dockerCliCommand'."
    }

    Write-Host 'Note that this script assumes that you have already set up your SecretKey, AccessKey, and AWS region using the ''aws configure'' command.'
    [string] $ECRRootUrl = "$AWSAccountId.dkr.ecr.$AWSRegion.amazonaws.com"
    [string] $ECRNameWithTag = "$($ECRName):latest"
    [string] $ECRContainerUrlWithTag = "$ECRRootUrl/$ECRNameWithTag"
}
process
{
    $params = `
    @(
        'ecr',
        "get-login-password",
        '--region',
        "$AWSRegion"
    )
    [string] $dockerLoginPassword = Exec `
        "Fetch docker logon password for AWS account with ID '$AWSAccountID' in region '$AWSRegion'" `
        $awsCliCommand `
        $params `
        -SuppressOutput

    $params = `
    @(
        "login",
        "--username",
        "AWS"
        "--password",
        "$dockerLoginPassword",
        "$ECRRootUrl"
    )
    Exec "Get temporary token for docker" $dockerCliCommand $params -SuppressOutput | Out-Null

    [string[]] $params = `
    @(
        'build',
        '-t',
        "$ECRName",
        "$QLedgerGitRepositoryFullDirectoryPath"
    )
    Exec `
        "Build container named '$ECRName' defined in '$QLedgerGitRepositoryFullDirectoryPath'" `
        $dockerCliCommand `
        $params `
        -SuppressOutput | Out-Null

    [string[]] $params = `
    @(
        'tag',
        "$ECRNameWithTag",
        "$ECRContainerUrlWithTag"
    )

    Exec `
        "Tag container withn name '$ECRName' as '$ECRNameWithTag' for ECRUrl '$ECRContainerUrlWithTag'" `
        $dockerCliCommand `
        $params `
        -SuppressOutput | Out-Null

    [string[]] $params = `
    @(
        'push',
        "$ECRContainerUrlWithTag"
    )

    Exec "Push container named '$ECRName' to '$ECRContainerUrlWithTag'..." $dockerCliCommand $params -SuppressOutput | Out-Null
    return $ECRContainerUrlWithTag
}
