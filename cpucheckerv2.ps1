# Updated Script: AzureRegionalVcpuChecker_Filtered.ps1
# Version: 1.7.4
# Date: YYYY-MM-DD

# Define parameters
param (
    [string[]]$SubscriptionIds = @("4a660082-72db-449f-8041-1f8d83cb35bc"),
    [string]$Region = "westus3",
    [switch]$DetailedQuotaOutput
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

function Format-Restrictions {
    param (
        [array]$Restrictions
    )

    if ($null -eq $Restrictions) {
        return "None"
    }

    $formattedRestrictions = $Restrictions | ForEach-Object {
        "Type: $($_.Type), Reason: $($_.ReasonCode), Locations: $($_.RestrictionInfo.Locations -join ", ")"
    }
    return ($formattedRestrictions -join "; ")
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

function Get-RegionalVcpuAvailability {
    param (
        [string]$Region,
        [switch]$DetailedOutput
    )

    try {
        $allQuotas = Get-AzVMUsage -Location "$Region" -ErrorAction Stop

        if ($DetailedOutput) {
            Write-Log -Message "Available quota entries in region $($Region):" -Type "Info"
            $allQuotas | ForEach-Object { Write-Log -Message "  Name: $($_.Name.Value), CurrentValue: $($_.CurrentValue), Limit: $($_.Limit)" -Type "Info" }
        }

        $quota = $allQuotas | Where-Object { $_.Name.Value -eq "cores" }
        if ($null -ne $quota) {
            $available = [int]$quota.Limit - [int]$quota.CurrentValue
            return @{ Limit = $quota.Limit; CurrentValue = $quota.CurrentValue; Available = $available }
        } else {
            Write-Log -Message "No matching vCPU data found for region: $($Region)." -Type "Warning"
            return $null
        }
    } catch {
        Write-Log -Message "Error retrieving vCPU data for region: $($Region). Details: $_" -Type "Error"
        return $null
    }
}

function Get-SkuFamilyQuota {
    param (
        [string]$Region
    )

    try {
        $vmSkus = Get-AzComputeResourceSku -Location "$Region" -ErrorAction Stop

        # Filter only D-series and E-series SKUs
        $filteredSkus = $vmSkus | Where-Object {
            ($_.ResourceType -eq "virtualMachines") -and
            ($_.Name -match "^(Standard_D|Standard_E).+s")
        }

        Write-Log -Message "Available D-series and E-series SKU families in region $Region that support Premium Disks:" -Type "Info"

        foreach ($sku in $filteredSkus) {
            if ($sku.LocationInfo) {
                foreach ($info in $sku.LocationInfo) {
                    $zones = if ($info.Zones) { $info.Zones -join ", " } else { "None" }
                    $restrictions = Format-Restrictions -Restrictions $sku.Restrictions

                    Write-Log -Message "SKU: $($sku.Name), Location: $($info.Location), Zones: $zones, Restrictions: $restrictions" -Type "Info"
                }
            } else {
                Write-Log -Message "SKU: $($sku.Name), Zones: None (No LocationInfo available), Restrictions: None" -Type "Info"
            }
        }
    } catch {
        Write-Log -Message "Error retrieving SKU family data for region: $Region. Details: $_" -Type "Error"
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

    Write-Log -Message "Retrieving vCPU availability for region: $($Region)" -Type "Info"
    $vcpuData = Get-RegionalVcpuAvailability -Region $Region -DetailedOutput:$DetailedQuotaOutput

    if ($vcpuData) {
        Write-Log -Message "vCPU Availability for Region: $($Region)" -Type "Info"
        Write-Log -Message "  Limit: $($vcpuData.Limit)" -Type "Info"
        Write-Log -Message "  Current Usage: $($vcpuData.CurrentValue)" -Type "Info"
        Write-Log -Message "  Available: $($vcpuData.Available)" -Type "Info"
    } else {
        Write-Log -Message "No vCPU data available for region: $($Region) in subscription: $($SubscriptionId)." -Type "Warning"
    }

    Write-Log -Message "Retrieving D-series and E-series SKU family quota for region: $($Region)" -Type "Info"
    Get-SkuFamilyQuota -Region $Region

    Write-Log -Message "==========================================" -Type "Info"
}

Write-Log -Message "All specified subscriptions have been processed." -Type "Info"
