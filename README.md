# Crossroads.Client

Unofficial PowerShell client for the [Gravitate Crossroads Integration API](https://docs.gravitate.energy/docs/crossroads-api/index.html).

## Scope

The module handles Crossroads authentication and POST requests. It does not contain customer mappings, credentials, tenant values, lifecycle rules, or send-state caching.

## Usage

```powershell
Install-Module Crossroads.Client
Import-Module Crossroads.Client

$token = Get-CrossroadsToken `
  -BaseUrl $env:CROSSROADS_BASE_URL `
  -TokenPath '/auth/token' `
  -ClientId $env:CROSSROADS_CLIENT_ID `
  -ClientSecret $env:CROSSROADS_CLIENT_SECRET `
  -GrantType 'password'

Invoke-CrossroadsRequest `
  -BaseUrl $env:CROSSROADS_BASE_URL `
  -Path '/v1/order/get' `
  -Body @{ order_number = '123' } `
  -Token $token `
  -Tenant 'tenant-a' `
  -DestinationTenant 'tenant-b' `
  -ReadOnly
```

Crossroads uses POST routes for both reads and writes. Pass `-ReadOnly` or `-AllowWrite` explicitly. Treat returned access tokens as bearer secrets and do not log them.

## Testing

```powershell
Invoke-Pester ./tests
Test-ModuleManifest ./Crossroads.Client/Crossroads.Client.psd1
```

## Versioning

Tags select the major and minor version (`v1.2`). The patch version is the number of commits since that tag. Commits to `main` publish after CI; an existing gallery version is skipped.
