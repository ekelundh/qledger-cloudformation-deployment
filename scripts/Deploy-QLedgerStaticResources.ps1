#Requires -Version 6.0

# Quick and dirty script to get ECR and S3 bucket up.
# S3 bucket will be filled with CF templates needed to deploy QLedger

[CmdletBinding()]
param (
    [Parameter()]
    [string] $S3BucketName = 'qledger-cloudformation-templates',

    [Parameter()]
    [string] $ECRName = 'qledger',

    [Parameter()]
    [Switch] $Update
)
begin
{
    $ErrorActionPreference = "Stop"
    [string] $rootDirectory = Split-Path (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent) -Parent
    [string] $commonScriptsPath = Join-Path $rootDirectory 'scripts' 'common.ps1'
    . $commonScriptsPath

    if ([string]::IsNullOrWhitespace($S3BucketName))
    {
        throw "S3BucketName must be non-empty."
    }
    if ([string]::IsNullOrWhitespace($ECRName))
    {
        throw "ECRName must be non-empty."
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

    [string] $stackName = 'qledger-deployment-resources'
    [string] $cloudFormationTemplatePath = Join-Path $rootDirectory 'qledger-static-prerequisites.yml'
    [string] $cloudFormationAction = if ($Update) { 'update' } else { 'create' }
}
process
{
    # Always delete S3 bucket as we will will re-upload the templates after updating/recreating stack
    [string[]] $params = `
    @(
        's3',
        'rb',
        "s3://$S3BucketName",
        "--force"
    )
    try
    {
        Exec "Empty S3 bucket with name '$S3BucketName'" $awsCliCommand $params -SuppressOutput | Out-Null
    }
    catch
    {
        Write-Host "Failed to empty bucket '$S3BucketName'. Continuing..."
    }


        
    if (!$Update)
    {
        
        Write-Host "Update flag not specified. Assuring stack $stackName does not exist."
        
        # Delete images in ECR repository as we cannot delete the repository using cloudformation if it has images
        try
        {
            [string[]] $params = `
            @(
                'ecr',
                'list-images',
                '--repository-name',
                "$ECRName"
            )
            [psobject] $imageIds = (((Exec "Fetch imageIds for ECR '$ECRNAME'" $awsCliCommand $params -SuppressOutput) -join '') | ConvertFrom-Json).ImageIds
            if ($imageIds.Length -gt 0)
            {
                [string[]] $params = `
                @(
                    'ecr',
                    'batch-delete-image',
                    '--repository-name',
                    "$ECRName"
                    "--image-ids"
                )
                foreach ($imageId in $imageIds)
                {
                    Write-Host "Found image with tag '$($imageId.imageTag)'."
                    $params+=@("imageTag=$($imageId.imageTag)")
                }
                Exec "Delete images found in ECR '$ECRNAME'" $awsCliCommand $params -SuppressOutput | Out-Null
            }
        }
        catch
        {
            Write-Host "Failed to empty ECR '$ECRName'. Continuing..."
        }
        
        $params = `
        @(
            'cloudformation',
            'delete-stack',
            '--stack-name',
            "$stackName"
        )
        Exec "Delete stack '$stackName'" $awsCliCommand $params -SuppressOutput | Out-Null

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

    $params = `
    @(
        'cloudformation',
        "$cloudFormationAction-stack",
        '--stack-name',
        "$stackName",
        "--template-body",
        "file://$cloudFormationTemplatePath",
        "--parameters",
        "ParameterKey=S3BucketName,ParameterValue=$S3BucketName"
        "ParameterKey=ECRName,ParameterValue=$ECRName"
    )
    Exec "'$cloudFormationAction' stack '$stackName'" $awsCliCommand $params -SuppressOutput | Out-Null

    $params = `
    @(
        'cloudformation',
        'wait',
        "stack-$cloudFormationAction-complete"
        '--stack-name',
        "$stackName"
    )
    Exec "Wait '$cloudFormationAction' complete for '$stackName'" $awsCliCommand $params -SuppressOutput

    [string] $infrastructureTemplatesFolder = Join-Path $rootDirectory 'infrastructure'
    $params = `
    @(
        's3',
        'sync',
        "$infrastructureTemplatesFolder",
        "s3://$S3BucketName/infrastructure"

    )
    Exec "Upload CloudFormation Templates in '$infrastructureTemplatesFolder ' to bucket '$S3BucketName'" $awsCliCommand $params | Out-Null
    
    [string] $serviceTemplatesFolder = Join-Path $rootDirectory 'service'
    $params = `
    @(
        's3',
        'sync',
        "$serviceTemplatesFolder",
        "s3://$S3BucketName/service"

    )
    Exec "Upload CloudFormation Templates in '$serviceTemplatesFolder ' to bucket '$S3BucketName'" $awsCliCommand $params | Out-Null

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
