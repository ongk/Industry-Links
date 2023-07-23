# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

<#
    .Synopsis
    Creates a Power Platform custom connector.

    .Description
    Creates Power Platform custom connector in the environment of your currently
    active PAC CLI auth profile.

    .Parameter CustomConnectorAssets
    The path to the folder containing assets for the custom connector such as
    the icon, API definition file, API properties file and the settings.json file.

    .Example
    # Create a custom connector
    New-CustomConnector -CustomConnectorAssets output/ContosoCustomConnector
#>
function New-CustomConnector {
    Param (
        [Parameter(Mandatory = $true, HelpMessage = "The path containing the custom connector assets")]
        [string] $CustomConnectorAssets
    )

    try {
        pac connector create --settings-file "$CustomConnectorAssets/settings.json"
    }
    catch {
        Write-Error "An error occurred while creating the custom connector: $($_.Exception.Message)"
        Exit 1
    }
}

<#
    .Synopsis
    Generates the asset configuration files to create a Power Platform custom connector.

    .Description
    Generates the asset files required to create a Power Platform custom connector,
    which include the API definition file, API properties file, settings.json file,
    the icon and the custom script file (if required).

    .Parameter ConfigFile
    The configuration file that defines the location of the required files to create
    the custom connector and the configuration for OAuth 2.0 authentication.

    .Parameter OutputDirectory
    The directory where the generated custom connector assets will be saved.
    If it doesn't exist, it will be created.

    .Example
    # Generate the assets for a Power Platform custom connector
    New-CustomConnectorConfig -ConfigFile config.json -OutputDirectory output
#>
function New-CustomConnectorConfig {
    Param (
        [Parameter(Mandatory = $true, HelpMessage = "The path to the configuration file.")]
        [string] $ConfigFile,
        [Parameter(Mandatory = $true, HelpMessage = "The path to a directory that will store the generated assets.")]
        [string] $OutputDirectory
    )
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

        if (!(Test-Path $OutputDirectory)) {
            New-Item -Name $OutputDirectory -ItemType Directory | Out-Null
        }

        pac connector init --outputDirectory $OutputDirectory --generate-settings-file | Out-Null

        # Copy the API definition to the output directory
        Copy-Item $config.apiDefinition "$OutputDirectory/apiDefinition.json"

        # Configure the authentication model of the API using the API definition
        Configure-AuthenticationOptions -ConnectorAssetsPath $OutputDirectory -ConfigFile $ConfigFile

        $iconFile = $config.icon
        if (Test-Path $iconFile) {
            # Copy the icon to the output directory and update the settings file
            Copy-Item $iconFile "$OutputDirectory/icon.png"
            $settings = (Get-Content "$OutputDirectory/settings.json" -Raw | ConvertFrom-Json)
            $settings.icon = "icon.png"
            $settings | ConvertTo-Json -Depth 100 | Out-File "$OutputDirectory/settings.json" -Force
        }
        else {
            throw "Icon file not found at $iconFile"
        }
    }
    catch {
        Write-Error "An error occurred while configuring the custom connector files: $($_.Exception.Message)"
        Exit 1
    }
}

function Get-ApiKeyConnectionParameters {
    return @{
        "api_key" = @{
            "type"         = "securestring"
            "uiDefinition" = @{
                "displayName" = "API Key"
                "description" = "The API Key to authenticate with the API"
                "tooltip"     = "Provide your API Key"
                "constraints" = @{
                    "tabIndex"  = 2
                    "clearText" = $false
                    "required"  = "true"
                }
            }
        }
    }
}

function Get-BasicAuthConnectionParameters {
    return @{
        "username" = @{
            "type"         = "securestring"
            "uiDefinition" = @{
                "displayName" = "Username"
                "description" = "The username to authenticate with the API"
                "tooltip"     = "Provide your API username"
                "constraints" = @{
                    "tabIndex"  = 2
                    "clearText" = $true
                    "required"  = "true"
                }
            }
        }
        "password" = @{
            "type"         = "securestring"
            "uiDefinition" = @{
                "displayName" = "Password"
                "description" = "The password to authenticate with the API"
                "tooltip"     = "Provide your API password"
                "constraints" = @{
                    "tabIndex"  = 3
                    "clearText" = $false
                    "required"  = "true"
                }
            }
        }
    }
}

function Get-AadAccessCodeConnectionParameters {
    param (
        [string] $clientId,
        [string] $scopes,
        [string] $resourceUri,
        [string] $tenantId
    )
    return @{
        "token"          = @{
            "type"          = "oauthSetting"
            "oAuthSettings" = @{
                "identityProvider" = "aad"
                "clientId"         = $clientId
                "scopes"           = $scopes
                "redirectMode"     = "Global"
                "redirectUrl"      = "https://global.consent.azure-apim.net/redirect"
                "properties"       = @{
                    "IsFirstParty"                   = "False"
                    "IsOnbehalfofLoginSupported"     = $true
                    "AzureActiveDirectoryResourceId" = $resourceUri
                }
                "customParameters" = @{
                    "loginUrl"              = @{
                        "value" = "https://login.microsoftonline.com"
                    }
                    "tenantId"              = @{
                        "value" = $tenantId
                    }
                    "resourceUri"           = @{
                        "value" = $resourceUri
                    }
                    "enableOnbehalfOfLogin" = @{
                        "value" = "false"
                    }
                }
            }
        }
        "token:TenantId" = @{
            "type"         = "string"
            "metadata"     = @{
                "sourceType" = "AzureActiveDirectoryTenant"
            }
            "uiDefinition" = @{
                "constraints" = @{
                    "required" = "false"
                    "hidden"   = "true"
                }
            }
        }
    }
}

function Get-GenericOAuthAccessCodeConnectionParameters {
    param (
        [string] $clientId,
        [string] $scopes,
        [string] $authorizationUrl,
        [string] $tokenUrl,
        [string] $refreshUrl
    )

    return @{
        "token" = @{
            "type"          = "oauthSetting"
            "oAuthSettings" = @{
                "identityProvider" = "oauth2"
                "clientId"         = $clientId
                "scopes"           = $scopes
                "redirectMode"     = "Global"
                "redirectUrl"      = "https://global.consent.azure-apim.net/redirect"
                "properties"       = @{
                    "IsFirstParty"               = "False"
                    "IsOnbehalfofLoginSupported" = $false
                }
                "customParameters" = @{
                    "authorizationUrl" = @{
                        "value" = $authorizationUrl
                    }
                    "tokenUrl"         = @{
                        "value" = $tokenUrl
                    }
                    "refreshUrl"       = @{
                        "value" = $refreshUrl
                    }
                }
            }
        }
    }
}

function Get-GenericOAuthClientCredentialsConnectionParameters {
    return @{
        "clientId"     = @{
            "type"         = "string"
            "uiDefinition" = @{
                "displayName" = "Client ID"
                "description" = "The Client ID of the API application."
                "tooltip"     = "Provide your Client ID."
                "constraints" = @{
                    "tabIndex" = 2
                    "required" = "true"
                }
            }
        }
        "clientSecret" = @{
            "type"         = "securestring"
            "uiDefinition" = @{
                "displayName" = "Client Secret"
                "description" = "The Client Secret of the API application."
                "tooltip"     = "Provide your Client Secret."
                "constraints" = @{
                    "tabIndex"  = 3
                    "clearText" = $false
                    "required"  = "true"
                }
            }
        }
    }
}

function Get-GenericOAuthClientCredentialsPolicyTemplates {
    param (
        [string] $tokenUrl,
        [string[]] $scopes
    )
    $policyTemplateInstances = @(
        @{
            "TemplateId" = "setheader"
            "Title"      = "Set HTTP header - Token URL"
            "Parameters" = @{
                "x-ms-apimTemplateParameter.name"         = "tokenUrl"
                "x-ms-apimTemplateParameter.value"        = $tokenUrl
                "x-ms-apimTemplateParameter.existsAction" = "override"
                "x-ms-apimTemplate-policySection"         = "Request"
            }
        },
        @{
            "TemplateId" = "setheader"
            "Title"      = "Set HTTP header - Client ID"
            "Parameters" = @{
                "x-ms-apimTemplateParameter.name"         = "clientId"
                "x-ms-apimTemplateParameter.value"        = "@connectionParameters('clientId','')"
                "x-ms-apimTemplateParameter.existsAction" = "override"
                "x-ms-apimTemplate-policySection"         = "Request"
            }
        },
        @{
            "TemplateId" = "setheader"
            "Title"      = "Set HTTP header - Client Secret"
            "Parameters" = @{
                "x-ms-apimTemplateParameter.name"         = "clientSecret"
                "x-ms-apimTemplateParameter.value"        = "@connectionParameters('clientSecret','')"
                "x-ms-apimTemplateParameter.existsAction" = "override"
                "x-ms-apimTemplate-policySection"         = "Request"
            }
        }
    )

    if ($scopes) {
        $policyTemplateInstances += @{
            "TemplateId" = "setheader"
            "Title"      = "Set HTTP header - Scope"
            "Parameters" = @{
                "x-ms-apimTemplateParameter.name"         = "scope"
                "x-ms-apimTemplateParameter.value"        = ($scopes -join " ")
                "x-ms-apimTemplateParameter.existsAction" = "override"
                "x-ms-apimTemplate-policySection"         = "Request"
            }
        }
    }
    return $policyTemplateInstances
}

function Configure-AuthenticationOptions {
    Param(
        [string] $ConnectorAssetsPath,
        [string] $ConfigFile
    )

    $apiDefinitionPath = "$ConnectorAssetsPath/apiDefinition.json"
    $apiPropertiesPath = "$ConnectorAssetsPath/apiProperties.json"

    $securityDefinition = (Get-Content $apiDefinitionPath -Raw | ConvertFrom-Json).securityDefinitions
    $connectionParameters = @{}
    $policyTemplateInstances = $null
    $customCodePath = $null

    # Set the connection parameters based on the authentication model of the API
    switch ($securityDefinition.PSObject.Properties.Value.type) {
        "apiKey" {
            $connectionParameters = Get-ApiKeyConnectionParameters
        }
        "basic" {
            $connectionParameters = Get-BasicAuthConnectionParameters
        }
        "oauth2" {
            # Get OAuth 2.0 values from API definition
            $apiDefintionAuth = $securityDefinition.PSObject.Properties.Value
            $scopes = @()

            # Get the scopes from the API definition if they exist
            if (Get-Member -inputobject $apiDefintionAuth -name "scopes" -Membertype Properties) {
                $scopes = @($apiDefintionAuth.scopes.PSObject.Properties.Name)
            }

            # Read the configuration file and get the OAuth2.0 values
            $oauthConfig = (Get-Content $ConfigFile -Raw | ConvertFrom-Json).oauth2

            # Check auth flow type
            if ($apiDefintionAuth.flow -eq "accessCode") {
                # Currently, only access code flow is supported in this script for AAD
                $isAad = (($apiDefintionAuth.authorizationUrl -like "*login.microsoftonline.com*") -or ($apiDefintionAuth.tokenUrl -like "*login.microsoftonline.com*"))

                if ($isAad) {
                    $connectionParameters = Get-AadAccessCodeConnectionParameters -clientId $oauthConfig.clientId -scopes $scopes -resourceUri $oauthConfig.resourceUri -tenantId $oauthConfig.tenantId

                }
                else {
                    $connectionParameters = Get-GenericOAuthAccessCodeConnectionParameters -clientId $oauthConfig.clientId -scopes $scopes -authorizationUrl $apiDefintionAuth.authorizationUrl -tokenUrl $apiDefintionAuth.tokenUrl -refreshUrl $apiDefintionAuth.refreshUrl
                }

                # Swagger 2.0 specification calls the client credentials flow "application" flow
            }
            elseif ($apiDefintionAuth.flow -eq "application") {
                $connectionParameters = Get-GenericOAuthClientCredentialsConnectionParameters

                $policyTemplateInstances = Get-GenericOAuthClientCredentialsPolicyTemplates -tokenUrl $apiDefintionAuth.tokenUrl -scopes $scopes

                $customCodePath = "$PSScriptRoot/customConnector/assets/clientCredentialsAuthFlow.csx"
            }
        }
        Default {
            Write-Output "No authentication model found. No configuration will be completed."
        }
    }

    # Get the API properties
    $apiProperties = Get-Content $apiPropertiesPath -Raw | ConvertFrom-Json

    # Add the authentication connection parameters to the API Properties
    if ($connectionParameters) {
        $apiProperties.properties.connectionParameters = $connectionParameters
    }

    # Add the policy template instances to the API Properties
    if ($policyTemplateInstances) {
        $apiProperties.properties | Add-Member -MemberType NoteProperty -Name "policyTemplateInstances" -Value $policyTemplateInstances
    }

    # Output the new API properties configuration to the output directory
    $apiProperties | ConvertTo-Json -Depth 100 | Out-File $apiPropertiesPath -Force

    # Update the output settings.json to point to custom code if exists
    if ($customCodePath) {
        $settings = (Get-Content "$ConnectorAssetsPath/settings.json" -Raw | ConvertFrom-Json)
        $settings.script = "script.csx"
        $settings | ConvertTo-Json -Depth 100 | Out-File "$ConnectorAssetsPath/settings.json" -Force

        Copy-Item $customCodePath "$ConnectorAssetsPath/script.csx"
    }
}

Export-ModuleMember -Function New-CustomConnectorConfig
Export-ModuleMember -Function New-CustomConnector