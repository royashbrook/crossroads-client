@{
  RootModule = 'Crossroads.Client.psm1'
  ModuleVersion = '0.1.0'
  GUID = '0685DAB3-9A35-40C3-BE94-DEDA22AA8628'
  Author = 'Roy Ashbrook'
  CompanyName = 'Community'
  Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
  Description = 'Unofficial PowerShell client for the Gravitate Crossroads Integration API.'
  PowerShellVersion = '7.2'
  FunctionsToExport = @('Get-CrossroadsToken', 'Invoke-CrossroadsRequest')
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
  PrivateData = @{
    PSData = @{
      Tags = @('Crossroads', 'Gravitate', 'REST', 'API')
      LicenseUri = 'https://github.com/royashbrook/crossroads-client/blob/main/LICENSE'
      ProjectUri = 'https://github.com/royashbrook/crossroads-client'
      ReleaseNotes = 'Initial private package extraction.'
    }
  }
}
