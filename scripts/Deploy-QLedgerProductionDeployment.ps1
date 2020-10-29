#Requires -Version 6.0

# Quick and dirty script to get ECR and S3 bucket up.
# S3 bucket will be filled with CF templates needed to deploy QLedger

[CmdletBinding()]
param (
    [Parameter(ParameterSetName = 'ParametersFromJson')]
    [string] $ConfigFilePath,

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $VpcCIDR = '10.1.0.0/16',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $CloudFormationTemplateS3BucketName = 'qledger-cloudformation-templates',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $PublicSubnet1CIDR = '10.1.0.0/24',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $PublicSubnet2CIDR = '10.1.2.0/24',
    
    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $PrivateSubnet1CIDR = '10.1.4.0/24',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $PrivateSubnet2CIDR = '10.1.6.0/24',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $QLedgerContainerRepositoryUrl = '347708694192.dkr.ecr.us-east-1.amazonaws.com/qledger:latest',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $DatabaseUsername = 'postgres',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $DatabasePassword = 'Welcome1234',

    [Parameter(ParameterSetName = 'ParametersFromCLI')]
    [string] $QLedgerApiToken = 'Bonjour4321',

    [Parameter()]
    [switch] $Update
)
begin
{
    $ErrorActionPreference = "Stop"
    [string] $rootDirectory = Split-Path (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent) -Parent
    [string] $commonScriptsPath = Join-Path $rootDirectory 'scripts' 'common.ps1'
    . $commonScriptsPath

    [psobject] $deploymentSettings = switch ($PSCmdlet.ParameterSetName) `
    {
        'ParametersFromJson' 
        {
            if (!(Test-Path $ConfigFilePath))
            {
                throw "Could not find JSON configuration file at '$configFilePath'."
            }

            Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
        }
        'ParametersFromCLI'
        {
            @{
                VpcCIDR = $VpcCIDR;
                CloudFormationTemplateS3BucketName = $CloudFormationTemplateS3BucketName;
                PublicSubnet1CIDR = $PublicSubnet1CIDR;
                PublicSubnet2CIDR = $PublicSubnet2CIDR;
                PrivateSubnet1CIDR  = $PrivateSubnet1CIDR; 
                PrivateSubnet2CIDR = $PrivateSubnet2CIDR;
                QLedgerContainerRepositoryUrl = $QLedgerContainerRepositoryUrl;
                DatabaseUsername = $DatabaseUsername;
                DatabasePassword = $DatabasePassword;
                QLedgerApiToken = $QledgerApiToken;
            }
        }
        default
        {
            throw "The ParameterSet '$PSCmdlet.ParameterSetName' is not yet supported."
        }
    }

    if ([string]::IsNullOrWhitespace($deploymentSettings.VpcCIDR))
    {
        throw "VpcCIDR must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.CloudFormationTemplateS3BucketName))
    {
        throw "CloudFormationTemplateS3BucketName must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.PublicSubnet1CIDR))
    {
        throw "PublicSubnet1CIDR must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.PublicSubnet2CIDR))
    {
        throw "PublicSubnet2CIDR must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.PrivateSubnet1CIDR))
    {
        throw "PrivateSubnet1CIDR must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.PrivateSubnet2CIDR))
    {
        throw "PrivateSubnet2CIDR must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.QLedgerContainerRepositoryUrl))
    {
        throw "QLedgerContainerRepositoryUrl must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.DatabaseUsername))
    {
        throw "DatabaseUsername must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.DatabasePassword))
    {
        throw "DatabasePassword must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($deploymentSettings.QledgerApiToken))
    {
        throw "QledgerApiToken must be non-empty."
    }

    [string] $awsCliCommand = 'aws'
    try
    {
        Get-Command $awsCliCommand | Out-Null
    }
    catch
    {
        throw "Failed to find AWS CLI. Please make sure the AWS CLI is installed. AWS CLI Command: '$awsCliCommand'."
    }

    [string] $stackName = 'qledger-production'
    [string] $cloudFormationTemplatePath = Join-Path $rootDirectory 'qledger-production-deployment.yml'
    [string] $cloudFormationAction = if ($Update) { 'update' } else { 'create' }

}
process
{
    if (!$Update)
    {
        Write-Host "Update flag not specified. Assuring stack '$stackName' does not exist."
        $params = `
        @(
            'cloudformation',
            'delete-stack',
            '--stack-name',
            "$stackName"
        )
        Exec "Delete cloudformation stack '$stackName'" $awsCliCommand $params | Out-Null

        $params = `
        @(
            'cloudformation',
            'wait',
            'stack-delete-complete'
            '--stack-name',
            "$stackName"
        )
        Exec "Wait until stack deletion completes" $awsCliCommand $params -SuppressOutput | Out-Null
    }

    Write-Host "Invoking CloudFormation with Template ""$cloudFormationTemplatePath""..."
    $params = `
    @(
        'cloudformation',
        "$cloudFormationAction-stack",
        '--stack-name',
        "$stackName",
        "--template-body",
        "file://$cloudFormationTemplatePath",
        "--parameters",
        "ParameterKey=VpcCIDR,ParameterValue=$($deploymentSettings.VpcCIDR)",
        "ParameterKey=CloudFormationTemplateS3BucketName,ParameterValue=$($deploymentSettings.CloudFormationTemplateS3BucketName)",
        "ParameterKey=PublicSubnet1CIDR,ParameterValue=$($deploymentSettings.PublicSubnet1CIDR)",
        "ParameterKey=PublicSubnet2CIDR,ParameterValue=$($deploymentSettings.PublicSubnet2CIDR)",
        "ParameterKey=PrivateSubnet1CIDR,ParameterValue=$($deploymentSettings.PrivateSubnet1CIDR)",
        "ParameterKey=PrivateSubnet2CIDR,ParameterValue=$($deploymentSettings.PrivateSubnet2CIDR)",
        "ParameterKey=QLedgerContainerRepositoryUrl,ParameterValue=$($deploymentSettings.QLedgerContainerRepositoryUrl)",
        "ParameterKey=DBUser,ParameterValue=$($deploymentSettings.DatabaseUsername)",
        "ParameterKey=DBPassword,ParameterValue=$($deploymentSettings.DatabasePassword)",
        "ParameterKey=ApiToken,ParameterValue=$($deploymentSettings.QLedgerApiToken)",
        '--capabilities',
        "CAPABILITY_NAMED_IAM"
    )
    Exec "'$cloudFormationAction' stack '$stackName'" $awsCliCommand $params | Out-Null

    $params = `
    @(
        'cloudformation',
        'wait',
        "stack-$cloudFormationAction-complete"
        '--stack-name',
        "$stackName"
    ) 
    Exec "Wait '$cloudFormationAction' complete for '$stackName'" $awsCliCommand $params -SuppressOutput | Out-Null

    $params = `
    @(
        'cloudformation',
        "describe-stacks"
        '--stack-name',
        "$stackName",
        '--query',
        'Stacks[0].Outputs'
    )
    return ((Exec "Get created stack output" $awsCliCommand $params -SuppressOutput) -join '') | ConvertFrom-Json
}