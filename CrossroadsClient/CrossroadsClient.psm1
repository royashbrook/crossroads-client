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
    -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
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
    [switch]$ThrowOnTransportError,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Token,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$Tenant,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$DestinationTenant,
    [Parameter(Mandatory, ParameterSetName = 'Read')] [switch]$ReadOnly,
    [Parameter(Mandatory, ParameterSetName = 'Write')] [switch]$AllowWrite,
    [ValidateRange(1, 3600)] [int]$TimeoutSec = 60,
    [ValidateNotNullOrEmpty()] [ValidatePattern('\S')] [string]$OriginInstance
  )

  $headers = @{
    Authorization = "Bearer $Token"
    Accept = 'application/json'
    'X-Tenant-Name' = $Tenant
    'X-Dest-Tenant-Name' = $DestinationTenant
  }
  if ($OriginInstance) { $headers['X-Origin-Instance-Name'] = $OriginInstance }
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
      -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec -SkipHttpErrorCheck -ErrorAction Stop
  }
  catch {
    if ($ThrowOnTransportError) { throw }
    return [pscustomobject]@{ http = 0; data = $_.Exception.Message }
  }

  $data = $null
  $parseError = $null
  if ($response.Content) {
    try { $data = ConvertFrom-Json -InputObject $response.Content -ErrorAction Stop }
    catch { $data = $response.Content; $parseError = $_.Exception.Message }
  }
  [pscustomobject]@{ http = [int]$response.StatusCode; data = $data; parse_error = $parseError }
}

function Send-CrossroadsMultipart {
  param([Net.Http.HttpClient]$Client, [uri]$Uri, [Net.Http.MultipartFormDataContent]$Form)
  $Client.PostAsync($Uri, $Form).GetAwaiter().GetResult()
}

function Send-CrossroadsBolImage {
  <#
  .SYNOPSIS
  Uploads a BOL PDF once. Source retrieval and delivery policy belong to the caller.
  .DESCRIPTION
  No redirects or retries. Transport exceptions propagate unchanged. A returned application
  status is not evidence of destination recovery or visible image metadata.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$BaseUrl,
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$Token,
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$Tenant,
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$DestinationTenant,
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$OrderNumber,
    [Parameter(Mandatory)][ValidatePattern('\S')][string]$BolNumber,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*\.pdf$')][string]$FileName,
    [Parameter(Mandatory)][byte[]]$Bytes,
    [Parameter(Mandatory)][switch]$AllowWrite,
    [ValidateRange(1, 3600)][int]$TimeoutSec = 30
  )
  if (-not $AllowWrite) { throw 'AllowWrite is required for an image upload.' }
  if ($Bytes.Length -lt 5 -or [Text.Encoding]::ASCII.GetString($Bytes, 0, 5) -cne '%PDF-') {
    throw 'Only PDF bytes may be uploaded.'
  }
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $form = [Net.Http.MultipartFormDataContent]::new()
  try {
    $client.Timeout = [timespan]::FromSeconds($TimeoutSec)
    $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
    $client.DefaultRequestHeaders.Add('X-Tenant-Name', $Tenant)
    $client.DefaultRequestHeaders.Add('X-Dest-Tenant-Name', $DestinationTenant)
    $form.Add([Net.Http.StringContent]::new($OrderNumber), 'order_number')
    $form.Add([Net.Http.StringContent]::new($BolNumber), 'bol_number')
    $file = [Net.Http.ByteArrayContent]::new($Bytes)
    $file.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/pdf')
    $form.Add($file, 'file', $FileName)
    $response = Send-CrossroadsMultipart $client ($BaseUrl.TrimEnd('/') + '/v1/order/save_bol_image') $form
    try {
      $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      $data = $null
      $parseError = $null
      if ($content) {
        try { $data = $content | ConvertFrom-Json -ErrorAction Stop }
        catch { $data = $content; $parseError = $_.Exception.Message }
      }
      [pscustomobject]@{ http = [int]$response.StatusCode; data = $data; parse_error = $parseError }
    } finally { $response.Dispose() }
  } finally { $form.Dispose(); $client.Dispose() }
}

Export-ModuleMember -Function Get-CrossroadsToken, Invoke-CrossroadsRequest, Send-CrossroadsBolImage
