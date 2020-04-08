# Load Az.Functions module constants
$constants = @{}
$constants["AllowedStorageTypes"] = @('Standard_GRS', 'Standard_RAGRS', 'Standard_LRS', 'Standard_ZRS', 'Premium_LRS')
$constants["RequiredStorageEndpoints"] = @('PrimaryEndpointFile', 'PrimaryEndpointQueue', 'PrimaryEndpointTable')
$constants["DefaultFunctionsVersion"] = '3'
$constants["NodeDefaultVersion"] = @{
    '2' = '~10'
    '3' = '~12'
}
$constants["RuntimeToDefaultVersion"] = @{
    'Linux' = @{
        '2'= @{
            'Node' = '10'
            'DotNet'= '2'
            'Python' = '3.7'
        }
        '3' =  @{
            'Node' = '10'
            'DotNet' = '3'
            'Python' = '3.7'
            'Java' = '8'
        }
    }
    'Windows' = @{
        '2'= @{
            'Node' = '10'
            'DotNet'= '2'
            'PowerShell' = '6'
            'Java' = '8'
        }
        '3' =  @{
            'Node' = '10'
            'DotNet' = '3'
            'PowerShell' = '6'
            'Java' = '8'
        }
    }
}
$constants["RuntimeToFormattedName"] = @{
    'node' = 'Node'
    'dotnet' = 'DotNet'
    'python' = 'Python'
    'java' = 'Java'
    'powershell' = 'PowerShell'
}
$constants["RuntimeToDefaultOSType"] = @{
    'DotNet'= 'Windows'
    'Node' = 'Windows'
    'Java' = 'Windows'
    'PowerShell' = 'Windows'
    'Python' = 'Linux'
}

# This are use for tab completion for the RuntimeVersion parameter in New-AzFunctionApp
$constants["RuntimeVersions"] = @{
    'DotNet'= @(2, 3)
    'Node' = @(8, 10, 12)
    'Java' = @(8)
    'PowerShell' = @(6)
    'Python' = @(3.6, 3.7)
}

foreach ($variableName in $constants.Keys)
{
    if (-not (Get-Variable $variableName -ErrorAction SilentlyContinue))
    {
        Set-Variable $variableName -value $constants[$variableName]
    }
}

function GetDefaultRuntimeVersion
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $FunctionsVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Runtime,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSType
    )

    if ($Runtime -eq "DotNet")
    {
        return $FunctionsVersion
    }

    $defaultVersion = $RuntimeToDefaultVersion[$OSType][$FunctionsVersion][$Runtime]

    if (-not $defaultVersion)
    {
        $errorMessage = "$Runtime is not supported in Functions version $FunctionsVersion for $OSType."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "RuntimeNotSuported" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    return $defaultVersion
}

function GetDefaultOSType
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Runtime
    )

    $defaultOSType = $RuntimeToDefaultOSType[$Runtime]

    if (-not $defaultOSType)
    {
        $errorMessage = "Failed to get default OS type for $Runtime."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "FailedToGetDefaultOSType" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    return $defaultOSType
}

function GetConnectionString
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StorageAccountName
    )

    $storageAccountInfo = GetStorageAccount -Name $StorageAccountName -ErrorAction SilentlyContinue
    if (-not $storageAccountInfo)
    {
        $errorMessage = "Storage account '$StorageAccountName' does not exist."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "StorageAccountNotFound" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    if ($storageAccountInfo.ProvisioningState -ne "Succeeded")
    {
        $errorMessage = "Storage account '$StorageAccountName' is not ready. Please run 'Get-AzStorageAccount' and ensure that the ProvisioningState is 'Succeeded'"
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "StorageAccountNotFound" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }
    
    $skuName = $storageAccountInfo.SkuName
    if (-not ($AllowedStorageTypes -contains $skuName))
    {
        $storageOptions = $AllowedStorageTypes -join ", "
        $errorMessage = "Storage type '$skuName' is not allowed'. Currently supported storage options: $storageOptions"
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "StorageTypeNotSupported" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    foreach ($endpoint in $RequiredStorageEndpoints)
    {
        if ([string]::IsNullOrEmpty($storageAccountInfo.$endpoint))
        {
            $errorMessage = "Storage account '$StorageAccountName' has no '$endpoint' endpoint. It must have table, queue, and blob endpoints all enabled."
            $exception = [System.InvalidOperationException]::New($errorMessage)
            ThrowTerminatingError -ErrorId "StorageAccountRequiredEndpointNotAvailable" `
                                  -ErrorMessage $errorMessage `
                                  -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                  -Exception $exception
        }
    }

    $resourceGroupName = ($storageAccountInfo.Id -split "/")[4]
    $keys = Az.Functions.internal\Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountInfo.Name -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($keys[0].Value))
    {
        $errorMessage = "Storage account '$StorageAccountName' has no key value."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "StorageAccountHasNoKeyValue" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    $accountKey = $keys[0].Value
    $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$accountKey"

    return $connectionString
}

function NewAppSetting
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Value
    )

    $setting = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.Api20150801.NameValuePair
    $setting.Name = $Name
    $setting.Value = $Value

    return $setting
}

function GetServicePlan
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    $plans = @(Az.Functions\Get-AzFunctionAppPlan)
    foreach ($plan in $plans)
    {
        if ($plan.Name -eq $Name)
        {
            return $plan
        }
    }
}

function GetStorageAccount
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    $storageAccounts = @(Az.Functions.internal\Get-AzStorageAccount)
    foreach ($account in $storageAccounts)
    {
        if ($account.Name -eq $Name)
        {
            return $account
        }
    }
}

function GetApplicationInsightsProject
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    $projects = @(Az.Functions.internal\Get-AzAppInsights)
    
    foreach ($project in $projects)
    {
        if ($project.Name -eq $Name)
        {
            return $project
        }
    }
}

function AddFunctionAppSettings
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $App
    )

    $App.AppServicePlan = ($App.ServerFarmId -split "/")[-1]
    $App.OSType = if ($App.kind.ToLower().Contains("linux")){ "Linux" } else { "Windows" }
    
    $currentSubscription = $null
    $resetDefaultSubscription = $false
    
    try
    {
        $settings = Get-AzWebAppApplicationSetting -Name $App.Name -ResourceGroupName $App.ResourceGroup -ErrorAction SilentlyContinue
        if ($null -eq $settings)
        {
            $resetDefaultSubscription = $true
            $currentSubscription = (Get-AzContext).Subscription.Id
            $null = Select-AzSubscription $App.SubscriptionId

            $settings = Az.Functions.internal\Get-AzWebAppApplicationSetting -Name $App.Name -ResourceGroupName $App.ResourceGroup -ErrorAction SilentlyContinue
            if ($null -eq $settings)
            {
                # We are unable to get the app settings, return the app
                return $App
            }
        }
    }
    finally
    {
        if ($resetDefaultSubscription)
        {
            $null = Select-AzSubscription $currentSubscription
        }
    }

    # Create a key value pair to hold the function app settings
    $applicationSettings = @{}
    foreach ($keyName in $settings.Property.Keys)
    {
        $applicationSettings[$keyName] = $settings.Property[$keyName]
    }

    # Add application settings
    $App.ApplicationSettings = $applicationSettings

    $runtimeName = $settings.Property["FUNCTIONS_WORKER_RUNTIME"]
    $App.Runtime = if (($null -ne $runtimeName) -and ($RuntimeToFormattedName.ContainsKey($runtimeName)))
                   {
                       $RuntimeToFormattedName[$runtimeName]
                   }
                   elseif ($applicationSettings.ContainsKey("DOCKER_CUSTOM_IMAGE_NAME"))
                   {
                       "Custom Image"
                   }
                   else {""}
    return $App
}

function GetFunctionApps
{
    param
    (
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [Object[]]
        $Apps,

        [System.String]
        $Location
    )

    if ($Apps.Count -eq 0)
    {
        return
    }

    $activityName = "Getting function apps"

    for ($index = 0; $index -lt $Apps.Count; $index++)
    {
        $app = $Apps[$index]

        $percentageCompleted = [int]((100 * ($index + 1)) / $Apps.Count)
        $status = "Complete: $($index + 1)/$($Apps.Count) function apps processed."
        Write-Progress -Activity "Getting function apps" -Status $status -PercentComplete $percentageCompleted
        
        if ($app.kind.ToLower().Contains("functionapp"))
        {
            if ($Location)
            {
                if ($app.Location -eq $Location)
                {
                    $app = AddFunctionAppSettings -App $app
                    $app
                }
            }
            else
            {
                $app = AddFunctionAppSettings -App $app
                $app
            }
        }
    }

    Write-Progress -Activity $activityName -Status "Completed" -Completed
}

function AddFunctionAppPlanWorkerType
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $AppPlan
    )

    # The GetList api for service plan that does not set the Reserved property, which is needed to figure out if the OSType is Linux.
    # TODO: Remove this code once  https://msazure.visualstudio.com/Antares/_workitems/edit/5623226 is fixed.
    if ($null -eq $AppPlan.Reserved)
    {
        # Get the service plan by name does set the Reserved property
        $planObject = Az.Functions.internal\Get-AzFunctionAppPlan -Name $AppPlan.Name -ResourceGroupName $AppPlan.ResourceGroup -SubscriptionId $AppPlan.SubscriptionId -ErrorAction SilentlyContinue
        $AppPlan = $planObject
    }

    $AppPlan.WorkerType = if ($AppPlan.Reserved){ "Linux" } else { "Windows" }

    return $AppPlan
}

function GetFunctionAppPlans
{
    param
    (
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [Object[]]
        $Plans,

        [System.String]
        $Location
    )

    if ($Plans.Count -eq 0)
    {
        return
    }

    $activityName = "Getting function app plans"

    for ($index = 0; $index -lt $Plans.Count; $index++)
    {
        $plan = $Plans[$index]
        
        $percentageCompleted = [int]((100 * ($index + 1)) / $Plans.Count)
        $status = "Complete: $($index + 1)/$($Plans.Count) function apps plans processed."
        Write-Progress -Activity $activityName -Status $status -PercentComplete $percentageCompleted

        try {
            if ($Location)
            {
                if ($plan.Location -eq $Location)
                {
                    $plan = AddFunctionAppPlanWorkerType -AppPlan $plan
                    $plan
                }
            }
            else
            {
                $plan = AddFunctionAppPlanWorkerType -AppPlan $plan
                $plan
            }
        }
        catch {
            continue;
        }
    }

    Write-Progress -Activity $activityName -Status "Completed" -Completed
}

function ValidateLocation
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Location,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Sku
    )

    $Location = $Location.Trim()
    $availableLocations = @(Az.Functions.internal\Get-AzFunctionAppAvailableLocation | ForEach-Object { $_.Name })
    if (-not ($availableLocations -contains $Location))
    {
        $errorMessage = "Location is invalid. Use: 'Get-AzFunctionAppAvailableLocation' to see available locations."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "LocationIsInvalid" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }
}

function ValidateFunctionName
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name
    )

    $result = Az.Functions.internal\Test-AzNameAvailability -Type Site -Name $Name

    if (-not $result.NameAvailable)
    {
        $errorMessage = "Function name '$Name' is not available.  Please try a different name."
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "FunctionAppNameIsNotAvailable" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }
}

function NormalizeSku
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Sku
    )    
    if ($Sku -eq "SHARED")
    {
        return "D1"
    }
    return $Sku
}

function CreateFunctionsIdentity
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $InputObject
    )

    if (-not ($InputObject.Name -and $InputObject.ResourceGroupName -and $InputObject.SubscriptionId))
    {
        $errorMessage = "Input object '$InputObject' is missing one or more of the following properties: Name, ResourceGroupName, SubscriptionId"
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "FailedToCreateFunctionsIdentity" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    $functionsIdentity = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.FunctionsIdentity
    $functionsIdentity.Name = $InputObject.Name
    $functionsIdentity.SubscriptionId = $InputObject.SubscriptionId
    $functionsIdentity.ResourceGroupName = $InputObject.ResourceGroupName

    return $functionsIdentity
}

function GetSkuName
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Sku
    )

    if (($Sku -eq "D1") -or ($Sku -eq "SHARED"))
    {
        return "SHARED"
    }
    elseif (($Sku -eq "B1") -or ($Sku -eq "B2") -or ($Sku -eq "B3") -or ($Sku -eq "BASIC"))
    {
        return "BASIC"
    }
    elseif (($Sku -eq "S1") -or ($Sku -eq "S2") -or ($Sku -eq "S3"))
    {
        return "STANDARD"
    }
    elseif (($Sku -eq "P1") -or ($Sku -eq "P2") -or ($Sku -eq "P3"))
    {
        return "PREMIUM"
    }
    elseif (($Sku -eq "P1V2") -or ($Sku -eq "P2V2") -or ($Sku -eq "P3V2"))
    {
        return "PREMIUMV2"
    }
    elseif (($Sku -eq "PC2") -or ($Sku -eq "PC3") -or ($Sku -eq "PC4"))
    {
        return "PremiumContainer"
    }
    elseif (($Sku -eq "EP1") -or ($Sku -eq "EP2") -or ($Sku -eq "EP3"))
    {
        return "ElasticPremium"
    }
    elseif (($Sku -eq "I1") -or ($Sku -eq "I2") -or ($Sku -eq "I3"))
    {
        return "Isolated"
    }

    $guidanceUrl = 'https://docs.microsoft.com/en-us/azure/azure-functions/functions-premium-plan#plan-and-sku-settings'

    $errorMessage = "Invalid sku (pricing tier), please refer to '$guidanceUrl' for valid values."
    $exception = [System.InvalidOperationException]::New($errorMessage)
    ThrowTerminatingError -ErrorId "InvalidSkuPricingTier" `
                          -ErrorMessage $errorMessage `
                          -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                          -Exception $exception
}

function ThrowTerminatingError
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorMessage,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory,

        [Exception]
        $Exception,

        [object]
        $TargetObject
    )

    if (-not $Exception)
    {
        $Exception = New-Object -TypeName System.Exception -ArgumentList $ErrorMessage
    }

    $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList ($Exception, $ErrorId, $ErrorCategory, $TargetObject)
    #$PSCmdlet.ThrowTerminatingError($errorRecord)
    throw $errorRecord
}

function GetFunctionAppDefaultNodeVersion
{
    param
    (
        [System.String]
        $FunctionsVersion,

        [System.String]
        $Runtime,

        [System.String]
        $RuntimeVersion
    )

    if ((-not $Runtime) -or ($Runtime -ne "node"))
    {
        return $NodeDefaultVersion[$FunctionsVersion]
    }

    if ($RuntimeVersion)
    {
        return "~$RuntimeVersion"
    }

    return $NodeDefaultVersion[$FunctionsVersion]
}

function GetLinuxFxVersion
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Runtime,

        [System.String]
        $RuntimeVersion
    )
    
    if (-not $RuntimeVersion)
    {
        $RuntimeVersion = $RuntimeToDefaultVersion[$Runtime]
    }

    $runtimeName = $Runtime.ToUpper()

    return "$runtimeName|$RuntimeVersion"
}

function GetErrorMessage
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Response
    )

    if ($Response.Exception.ResponseBody)
    {
        try
        {
            $details = ConvertFrom-Json $Response.Exception.ResponseBody
            if ($details.Message)
            {
                return $details.Message
            }
        }
        catch 
        {
            # Ignore the deserialization error
        }
    }
}

function GetSupportedRuntimes
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSType
    )

    if ($OSType -eq "Linux")
    {
        return $LinuxRuntimes
    }
    elseif ($OSType -eq "Windows")
    {
        return $WindowsRuntimes
    }

    throw "Unknown OS type '$OSType'"
}

function ValidateRuntimeAndRuntimeVersion
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $FunctionsVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Runtime,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RuntimeVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSType
    )

    if ($Runtime -eq "DotNet")
    {
        return
    }

    $runtimeVersionIsSupported = $false
    $supportedRuntimes = GetSupportedRuntimes -OSType $OSType
    
    foreach ($majorVersion in $supportedRuntimes[$Runtime].MajorVersions)
    {
        if ($majorVersion.DisplayVersion -eq $RuntimeVersion)
        {
            if ($majorVersion.SupportedFunctionsExtensionVersions -contains $FunctionsVersion)
            {
                $runtimeVersionIsSupported = $true
                break
            }
        }
    }

    if (-not $runtimeVersionIsSupported)
    {
        $errorMessage = "$Runtime version $RuntimeVersion in Functions version $FunctionsVersion for $OSType is not supported."
        $errorMessage += " For supported languages, please visit 'https://docs.microsoft.com/en-us/azure/azure-functions/functions-versions#languages'."
        $errorId = "InvalidRuntimeVersionFor" + $Runtime + "In" + $OSType
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId $errorId `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }
}

function GetWorkerVersion
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $FunctionsVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Runtime,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RuntimeVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSType
    )

    $workerRuntimeVersion = $null
    $supportedRuntimes = GetSupportedRuntimes -OSType $OSType

    foreach ($majorVersion in $supportedRuntimes[$Runtime].MajorVersions)
    {
        if ($majorVersion.DisplayVersion -eq $RuntimeVersion)
        {
            $workerRuntimeVersion = $majorVersion.runtimeVersion
            break
        }
    }

    if (-not $workerRuntimeVersion)
    {
        $errorMessage = "Falied to get runtime version for $Runtime $RuntimeVersion in Functions version $FunctionsVersion for $OSType."
        $errorId = "InvalidWorkerRuntimeVersionFor" + $Runtime + "In" + $OSType
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId $errorId `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }

    return $workerRuntimeVersion
}

function ValidateConsumptionPlanLocation
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Location
    )

    $Location = $Location.Trim()

    $availableLocations = @(Az.Functions.internal\Get-AzFunctionAppAvailableLocation -LinuxWorkersEnabled | ForEach-Object { $_.Name })

    if (-not ($availableLocations -contains $Location))
    {
        $locationOptions = $availableLocations -join ", "
        $errorMessage = "Location is invalid. Currently supported locations are: $locationOptions"
        $exception = [System.InvalidOperationException]::New($errorMessage)
        ThrowTerminatingError -ErrorId "LocationIsInvalid" `
                              -ErrorMessage $errorMessage `
                              -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                              -Exception $exception
    }
}

function ParseDockerImage
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DockerImageName
    )

    # Sample urls:
    # myacr.azurecr.io/myimage:tag
    # mcr.microsoft.com/azure-functions/powershell:2.0
    if ($DockerImageName.Contains("/"))
    {
        $index = $DockerImageName.LastIndexOf("/")
        $value = $DockerImageName.Substring(0,$index)
        if ($value.Contains(".") -or $value.Contains(":"))
        {
            return $value
        }
    }
}

# Set Linux and Windows supported runtimes
Class Runtime {
    [string]$Name
    [Object[]]$MajorVersions
}

Class MajorVersion {
    [string]$DisplayVersion
    [string]$RuntimeVersion
    [string[]]$SupportedFunctionsExtensionVersions
}

$LinuxRuntimes = @{}
$WindowsRuntimes = @{}

function SetLinuxandWindowsSupportedRuntimes
{
    foreach ($fileName in @("LinuxFunctionsStacks.json", "WindowsFunctionsStacks.json"))
    {
        $filePath = Join-Path "$PSScriptRoot/FunctionsStack" $fileName

        if (-not (Test-Path $filePath))
        {
            throw "Unable to create list of supported runtimes. File path '$filePath' does not exist."
        }

        $functionsStack = Get-Content -Path $filePath -Raw | ConvertFrom-Json

        foreach ($stack in $functionsStack.value)
        {
            $runtime = [Runtime]::new()
            $runtime.name = $stack.name

            foreach ($version in $stack.properties.majorVersions)
            {
                $majorVersion = [MajorVersion]::new()

                if ($version.displayVersion)
                {
                    $majorVersion.DisplayVersion = $version.displayVersion
                }
                $majorVersion.RuntimeVersion = $version.RuntimeVersion
                $majorVersion.SupportedFunctionsExtensionVersions = $version.supportedFunctionsExtensionVersions
                $runtime.MajorVersions += $majorVersion
            }

            if ($stack.type -like "*LinuxFunctions")
            {
                if (-not $LinuxRuntimes.ContainsKey($runtime.name))
                {
                    $LinuxRuntimes[$runtime.name] = $runtime
                }
            }
            elseif ($stack.type -like "*WindowsFunctions")
            {
                if (-not $WindowsRuntimes.ContainsKey($runtime.name))
                {
                    $WindowsRuntimes[$runtime.name] = $runtime
                }
            }
            else
            {
                throw "Unknown stack type '$($stack.type)'"
            }
        }
    }
}
SetLinuxandWindowsSupportedRuntimes

# New-AzFunction app ArgumentCompleter for the RuntimeVersion parameter
# The values of RuntimeVersion depend on the selection of the Runtime parameter
$GetRuntimeVersionCompleter = {

    param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($fakeBoundParameters.ContainsKey('Runtime'))
    {
        # RuntimeVersions is defined at the top of this file
        $RuntimeVersions[$fakeBoundParameters.Runtime] | Where-Object {
            $_ -like "$wordToComplete*"
        } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
    else
    {
        $RuntimeVersions.RuntimeVersion | ForEach-Object {$_}
    }
}
Register-ArgumentCompleter -CommandName New-AzFunctionApp -ParameterName RuntimeVersion -ScriptBlock $GetRuntimeVersionCompleter