# Script Name: AzureResourceProviderChecker.ps1
# Version: 1.4.0
# Date: YYYY-MM-DD

# Define parameters
param (
    [string[]]$SubscriptionIds = @("4a660082-72db-449f-8041-1f8d83cb35bc"),
    [string[]]$ResourceProviders = @("Microsoft.Compute", "Microsoft.Storage", "Microsoft.Network")
)

# Logging function
function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "Info" # Info, Error, Warning
    )

    switch ($Type) {
        "Info" { Write-Host "[INFO] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "Error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        default { Write-Host "[UNKNOWN] $Message" -ForegroundColor White }
    }
}

# Function to validate PowerShell version
function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Log -Message "This script requires PowerShell 7 or higher. Please update your PowerShell version." -Type "Error"
        exit 1
    }
}

# Function to validate the Az module
function Test-AzModule {
    param (
        [bool]$IsPS7OrHigher
    )

    if ($IsPS7OrHigher) {
        return Get-Module -ListAvailable -Name Az
    } else {
        return Get-Module -ListAvailable -Name Az*
    }
}

# Function to authenticate Azure session
function Start-AzSession {
    if (-not (Get-AzContext)) {
        Write-Log -Message "No active Azure session detected. Initiating authentication..." -Type "Warning"
        Connect-AzAccount -ErrorAction Stop | Out-Null
    } else {
        Write-Log -Message "Using existing Azure session." -Type "Info"
    }
}

# Function to set Azure subscription context
function Set-AzSubscriptionContext {
    param (
        [string]$SubscriptionId
    )

    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        Write-Log -Message "Subscription context successfully set to: $($SubscriptionId)" -Type "Info"
    } catch {
        Write-Log -Message "Failed to set context to subscription: $($SubscriptionId). Ensure the subscription ID is valid." -Type "Error"
        return $false
    }
    return $true
}

# Function to check resource provider registration
function Check-ResourceProvider {
    param (
        [string]$ProviderNamespace
    )

    try {
        $provider = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace -ErrorAction Stop
        if ($provider.RegistrationState -eq "Registered") {
            Write-Log -Message "Resource provider '$ProviderNamespace' is registered." -Type "Info"
        } else {
            Write-Log -Message "Resource provider '$ProviderNamespace' is NOT registered." -Type "Warning"
        }
    } catch {
        Write-Log -Message "Failed to check registration state for resource provider '$ProviderNamespace'. Details: $_" -Type "Error"
    }
}

# Function to check EncryptionAtHost for Microsoft.Compute
function Check-EncryptionAtHost {
    try {
        $featureStatus = Get-AzProviderFeature -ProviderNamespace "Microsoft.Compute" -FeatureName "EncryptionAtHost" -ErrorAction Stop
        if ($featureStatus.RegistrationState -eq "Registered") {
            Write-Log -Message "Feature 'EncryptionAtHost' in provider 'Microsoft.Compute' is enabled." -Type "Info"
        } else {
            Write-Log -Message "Feature 'EncryptionAtHost' in provider 'Microsoft.Compute' is NOT enabled." -Type "Warning"
        }
    } catch {
        Write-Log -Message "Failed to check feature 'EncryptionAtHost' in provider 'Microsoft.Compute'. Details: $_" -Type "Error"
    }
}

# Main script execution
Test-PowerShellVersion

$IsPS7OrHigher = $PSVersionTable.PSVersion.Major -ge 7
if (-not (Test-AzModule -IsPS7OrHigher $IsPS7OrHigher)) {
    Write-Log -Message "The Az module is not installed. Please install it using 'Install-Module -Name Az -AllowClobber -Scope CurrentUser' in PowerShell 7." -Type "Error"
    exit 1
}

Write-Log -Message "PowerShell version is sufficient, and the Az module is installed. Continuing script execution..." -Type "Info"

Start-AzSession

foreach ($SubscriptionId in $SubscriptionIds) {
    Write-Log -Message "==========================================" -Type "Info"
    Write-Log -Message "Processing subscription: $($SubscriptionId)" -Type "Info"
    Write-Log -Message "==========================================" -Type "Info"

    if (-not (Set-AzSubscriptionContext -SubscriptionId $SubscriptionId)) {
        Write-Log -Message "Skipping subscription: $($SubscriptionId) due to context setting failure." -Type "Warning"
        continue
    }

    foreach ($ProviderNamespace in $ResourceProviders) {
        Write-Log -Message "Checking resource provider: $ProviderNamespace" -Type "Info"
        Check-ResourceProvider -ProviderNamespace $ProviderNamespace

        # Always check EncryptionAtHost for Microsoft.Compute
        if ($ProviderNamespace -eq "Microsoft.Compute") {
            Check-EncryptionAtHost
        }
    }

    Write-Log -Message "==========================================" -Type "Info"
}

Write-Log -Message "All specified subscriptions have been processed." -Type "Info"
