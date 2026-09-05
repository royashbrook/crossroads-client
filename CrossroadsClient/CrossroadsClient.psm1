Set-StrictMode -Version Latest

function Get-CrossroadsToken {
  <#
  .SYNOPSIS
  Requests a bearer token from a Crossroads authentication endpoint.

  .DESCRIPTION
  Sends either explicit client credential fields or a caller-supplied form body. The returned
  token is a bearer secret. Do not write it to transcripts, logs, or verbose output.

  .EXAMPLE
  $token = Get-CrossroadsToken -BaseUrl 'https://crossroads.example/api' `
    -TokenPath '/auth/token' -ClientId $clientId -ClientSecret $clientSecret `
    -GrantType 'password'
  #>
  [CmdletBinding(DefaultParameterSetName = 'Credentials')]
  param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$BaseUrl,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$TokenPath,
    [Parameter(Mandatory, ParameterSetName = 'Credentials')] [string]$ClientId,
    [Parameter(Mandatory, ParameterSetName = 'Credentials')] [string]$ClientSecret,
    [Parameter(Mandatory, ParameterSetName = 'Credentials')] [string]$GrantType,
    [Parameter(Mandatory, ParameterSetName = 'Body')] [hashtable]$TokenBody,
    [ValidateRange(1, 3600)] [int]$TimeoutSec = 60
  )

  $body = if ($PSCmdlet.ParameterSetName -eq 'Body') {
    $TokenBody
  }
  else {
    @{
      grant_type = $GrantType
      client_id = $ClientId
      client_secret = $ClientSecret
    }
  }
  $response = Invoke-RestMethod -Method Post `
    -Uri ($BaseUrl.TrimEnd('/') + '/' + $TokenPath.TrimStart('/')) `
    -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec $TimeoutSec
  if ([string]::IsNullOrWhiteSpace($response.access_token)) {
    throw 'Crossroads token response was empty.'
  }
  $response.access_token
}

function Invoke-CrossroadsRequest {
  <#
  .SYNOPSIS
  Sends a POST request to the Crossroads Integration API.

  .DESCRIPTION
  Crossroads uses POST routes for both reads and writes. Callers must declare read-only or write
  intent explicitly. HTTP responses are normalized to an object with http and data properties.
  With RawJson, Body must be valid JSON text and is sent unchanged as UTF-8 bytes.

  .EXAMPLE
  Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
    -Path '/v1/order/get' -Body @{ order_number = '123' } -Token $token `
    -Tenant 'tenant-a' -DestinationTenant 'tenant-b' -ReadOnly
  #>
  [CmdletBinding(DefaultParameterSetName = 'Read')]
  param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$BaseUrl,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Path,
    [Parameter(Mandatory)] [object]$Body,
    [switch]$RawJson,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Token,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Tenant,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$DestinationTenant,
    [Parameter(Mandatory, ParameterSetName = 'Read')] [switch]$ReadOnly,
    [Parameter(Mandatory, ParameterSetName = 'Write')] [switch]$AllowWrite,
    [ValidateRange(1, 3600)] [int]$TimeoutSec = 60
  )

  $headers = @{
    Authorization = "Bearer $Token"
    Accept = 'application/json'
    'X-Tenant-Name' = $Tenant
    'X-Dest-Tenant-Name' = $DestinationTenant
  }
  $json = if ($RawJson) {
    if ($Body -isnot [string] -or -not (Test-Json -Json $Body -ErrorAction Stop)) {
      throw 'RawJson requires valid JSON text.'
    }
    ,[Text.Encoding]::UTF8.GetBytes($Body)
  }
  else { ConvertTo-Json -InputObject $Body -Depth 12 -Compress }
  try {
    $response = Invoke-WebRequest -Method Post `
      -Uri ($BaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/')) `
      -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec
    $data = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
    [pscustomobject]@{ http = [int]$response.StatusCode; data = $data }
  }
  catch {
    $responseProperty = $_.Exception.PSObject.Properties['Response']
    $response = if ($responseProperty) { $responseProperty.Value } else { $null }
    $content = if ($_.ErrorDetails) { "$($_.ErrorDetails.Message)" } else { '' }
    if ([string]::IsNullOrWhiteSpace($content) -and $response) {
      $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
      $content = $_.Exception.Message
    }
    $data = try { $content | ConvertFrom-Json } catch { $content }
    $http = if ($response) { [int]$response.StatusCode } else { 0 }
    [pscustomobject]@{ http = $http; data = $data }
  }
}

Export-ModuleMember -Function Get-CrossroadsToken, Invoke-CrossroadsRequest
