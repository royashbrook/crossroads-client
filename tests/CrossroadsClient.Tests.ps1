BeforeAll {
  $root = Split-Path $PSScriptRoot -Parent
  $modulePath = Join-Path $root 'CrossroadsClient' 'CrossroadsClient.psd1'
  Import-Module $modulePath -Force
}

Describe 'package boundary' {
  It 'has a valid manifest' {
    { Test-ModuleManifest $modulePath -ErrorAction Stop } | Should -Not -Throw
  }

  It 'exports only the public client commands' {
    @((Get-Module CrossroadsClient).ExportedFunctions.Keys | Sort-Object) -join ',' |
      Should -Be 'Get-CrossroadsToken,Invoke-CrossroadsRequest'
  }
}

Describe 'token contract' {
  BeforeEach {
    Mock Invoke-RestMethod -ModuleName CrossroadsClient {
      [pscustomobject]@{ access_token = 'test-token' }
    }
  }

  It 'sends explicit credential fields to the requested route' {
    $token = Get-CrossroadsToken -BaseUrl 'https://crossroads.example/api' `
      -TokenPath '/auth/token' -ClientId 'client-id' -ClientSecret 'client-secret' `
      -GrantType 'password'

    $token | Should -Be 'test-token'
    Should -Invoke Invoke-RestMethod -ModuleName CrossroadsClient -Times 1 -ParameterFilter {
      $Uri -eq 'https://crossroads.example/api/auth/token' -and
      $Body.grant_type -eq 'password' -and
      $Body.client_id -eq 'client-id' -and
      $Body.client_secret -eq 'client-secret'
    }
  }

  It 'accepts a caller-supplied token body' {
    Get-CrossroadsToken -BaseUrl 'https://crossroads.example/api' -TokenPath '/token' `
      -TokenBody @{ scope = 'carrier'; api_key = 'key' } | Should -Be 'test-token'

    Should -Invoke Invoke-RestMethod -ModuleName CrossroadsClient -Times 1 -ParameterFilter {
      $Body.scope -eq 'carrier' -and $Body.api_key -eq 'key'
    }
  }
}

Describe 'request contract' {
  BeforeEach {
    Mock Invoke-WebRequest -ModuleName CrossroadsClient {
      [pscustomobject]@{ StatusCode = 200; Content = '{"status":"synced"}' }
    }
  }

  It 'sends neutral tenant headers on a declared read' {
    $result = Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/get' -Body @{ order_number = '123' } -Token 'token' `
      -Tenant 'tenant-a' -DestinationTenant 'tenant-b' -ReadOnly

    $result.http | Should -Be 200
    Should -Invoke Invoke-WebRequest -ModuleName CrossroadsClient -Times 1 -ParameterFilter {
      $Headers['X-Tenant-Name'] -eq 'tenant-a' -and
      $Headers['X-Dest-Tenant-Name'] -eq 'tenant-b'
    }
  }

  It 'preserves a bare single-element array body' {
    $body = @(@{ order_number = '123' })
    Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/get' -Body $body -Token 'token' `
      -Tenant 'tenant-a' -DestinationTenant 'tenant-b' -ReadOnly | Out-Null

    Should -Invoke Invoke-WebRequest -ModuleName CrossroadsClient -Times 1 -ParameterFilter {
      $Body.StartsWith('[') -and $Body.EndsWith(']')
    }
  }

  It 'allows an explicitly declared write' {
    $result = Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/create' -Body @{ origin_order_number = '123' } -Token 'token' `
      -Tenant 'tenant-a' -DestinationTenant 'tenant-b' -AllowWrite

    $result.http | Should -Be 200
  }

  It 'sends raw JSON as unchanged UTF-8 without double encoding' {
    $text = '[ {"quantity":7900.0000000000000000,"other":1.2345678901234567e3,"name":"' + [char]0x00e9 + '\\path","optional":null} ]'
    Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/create' -Body $text -RawJson -Token token `
      -Tenant tenant-a -DestinationTenant tenant-b -AllowWrite | Out-Null

    Should -Invoke Invoke-WebRequest -ModuleName CrossroadsClient -Times 1 -Exactly -ParameterFilter {
      $Body -is [byte[]] -and [Text.Encoding]::UTF8.GetString($Body) -ceq $text
    }
  }

  It 'rejects invalid raw JSON before HTTP' {
    { Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/get' -Body '{broken' -RawJson -Token token `
      -Tenant tenant-a -DestinationTenant tenant-b -ReadOnly } | Should -Throw
    Should -Invoke Invoke-WebRequest -ModuleName CrossroadsClient -Times 0 -Exactly
  }

  It 'does not accept an object as raw JSON' {
    { Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/get' -Body @{} -RawJson -Token token `
      -Tenant tenant-a -DestinationTenant tenant-b -ReadOnly } | Should -Throw '*JSON text*'
    Should -Invoke Invoke-WebRequest -ModuleName CrossroadsClient -Times 0 -Exactly
  }

  It 'preserves non-http transport errors' {
    Mock Invoke-WebRequest -ModuleName CrossroadsClient { throw 'network down' }

    $result = Invoke-CrossroadsRequest -BaseUrl 'https://crossroads.example/api' `
      -Path '/v1/order/get' -Body @{} -Token 'token' `
      -Tenant 'tenant-a' -DestinationTenant 'tenant-b' -ReadOnly

    $result.http | Should -Be 0
    "$($result.data)" | Should -Match 'network down'
  }
}
