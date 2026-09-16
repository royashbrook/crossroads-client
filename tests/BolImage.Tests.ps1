BeforeAll {
  Import-Module "$PSScriptRoot/../CrossroadsClient/CrossroadsClient.psd1" -Force
  $imageArgs = @{ BaseUrl = 'https://api.example/api/'; Token = 'synthetic-token'; Tenant = 'source'; DestinationTenant = 'target'
    OrderNumber = '123'; BolNumber = 'BOL-1'; FileName = 'scan-7.pdf'; Bytes = [Text.Encoding]::ASCII.GetBytes('%PDF-test'); AllowWrite = $true }
}
Describe 'BOL image HTTP boundary' {
  BeforeEach {
    Mock Send-CrossroadsMultipart -ModuleName CrossroadsClient {
      $r = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK)
      $r.Content = [Net.Http.StringContent]::new('{"status":"error"}')
      return $r
    }
  }
  It 'posts the PDF and flat fields with route headers exactly once' {
    Mock Send-CrossroadsMultipart -ModuleName CrossroadsClient {
      $wire = $Form.ReadAsStringAsync().GetAwaiter().GetResult()
      $Uri.AbsoluteUri | Should -Be 'https://api.example/api/v1/order/save_bol_image'
      $Client.DefaultRequestHeaders.Authorization.Parameter | Should -Be 'synthetic-token'
      @($Client.DefaultRequestHeaders.GetValues('X-Tenant-Name'))[0] | Should -Be 'source'
      @($Client.DefaultRequestHeaders.GetValues('X-Dest-Tenant-Name'))[0] | Should -Be 'target'
      $Client.Timeout.TotalSeconds | Should -Be 30
      @($Form).Count | Should -Be 3
      foreach ($part in 'name=order_number','name=bol_number','name=file','filename=scan-7.pdf','%PDF-test') {
        $wire.Contains($part) | Should -BeTrue
      }
      $r = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK)
      $r.Content = [Net.Http.StringContent]::new('{"status":"error"}')
      $r
    }
    $r = Send-CrossroadsBolImage @imageArgs
    $r.http | Should -Be 200
    $r.data.status | Should -Be 'error'
    Should -Invoke Send-CrossroadsMultipart -ModuleName CrossroadsClient -Exactly -Times 1
  }
  It 'rejects non-PDF bytes before network' {
    $bad = $imageArgs.Clone(); $bad.Bytes = [Text.Encoding]::ASCII.GetBytes('html')
    { Send-CrossroadsBolImage @bad } | Should -Throw '*PDF*'
    Should -Invoke Send-CrossroadsMultipart -ModuleName CrossroadsClient -Times 0
  }
  It 'requires positive write intent' {
    $bad = $imageArgs.Clone(); $bad.AllowWrite = $false
    { Send-CrossroadsBolImage @bad } | Should -Throw '*AllowWrite*'
    Should -Invoke Send-CrossroadsMultipart -ModuleName CrossroadsClient -Times 0
  }
  It 'rejects path-bearing filenames' {
    $bad = $imageArgs.Clone(); $bad.FileName = '../scan.pdf'
    { Send-CrossroadsBolImage @bad } | Should -Throw
    Should -Invoke Send-CrossroadsMultipart -ModuleName CrossroadsClient -Times 0
  }
  It 'lets the original transport exception escape without a retry' {
    Mock Send-CrossroadsMultipart -ModuleName CrossroadsClient { throw [TimeoutException]::new('original socket timeout') }
    { Send-CrossroadsBolImage @imageArgs } | Should -Throw '*original socket timeout*'
    Should -Invoke Send-CrossroadsMultipart -ModuleName CrossroadsClient -Times 1 -Exactly
  }
  It 'returns non-JSON HTTP failures for caller disposition' {
    Mock Send-CrossroadsMultipart -ModuleName CrossroadsClient {
      $r = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::ServiceUnavailable)
      $r.Content = [Net.Http.StringContent]::new('unavailable')
      $r
    }
    $r = Send-CrossroadsBolImage @imageArgs
    $r.http | Should -Be 503
    $r.data | Should -Be 'unavailable'
    $r.parse_error | Should -Not -BeNullOrEmpty
  }
}
