param(
  [ValidateSet('Launch', 'Doctor', 'Drive', 'Evidence', 'Cleanup', 'All')]
  [string]$Phase = 'All'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$userCodex = Join-Path $env:USERPROFILE '.codex'
$toolRoot = Join-Path $userCodex 'tools\coursework-llvm'
$sdkDefault = Join-Path $toolRoot 'clang+llvm-23.1.4-x86_64-pc-windows-msvc'
$sdk = if ($env:LLVM_SDK_ROOT) { $env:LLVM_SDK_ROOT } else { $sdkDefault }
$deps = if ($env:LLVM_DEPS_ROOT) { $env:LLVM_DEPS_ROOT } else { Join-Path $toolRoot 'deps' }
$scratch = Join-Path $repo 'build\verify'
$evidenceRoot = Join-Path $repo '.verify\evidence'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runEvidence = Join-Path $evidenceRoot $runId
$sdkBin = Join-Path $sdk 'bin'
$llvmConfig = Join-Path $sdkBin 'llvm-config.exe'
$opt = Join-Path $sdkBin 'opt.exe'
$llc = Join-Path $sdkBin 'llc.exe'
$objdump = Join-Path $sdkBin 'llvm-objdump.exe'
$driver = Join-Path $scratch 'slp-opt.exe'

function Assert-Condition([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Get-VsDevCmd {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  Assert-Condition (Test-Path $vswhere) "Visual Studio discovery tool missing at $vswhere"
  $install = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  Assert-Condition ($LASTEXITCODE -eq 0 -and $install) 'Visual Studio 2022 x64 C++ tools are not installed.'
  $path = Join-Path $install 'Common7\Tools\VsDevCmd.bat'
  Assert-Condition (Test-Path $path) "Visual Studio developer environment missing at $path"
  return $path
}

function Invoke-Launch {
  Assert-Condition (Test-Path $llvmConfig) "LLVM SDK missing: $llvmConfig"
  $version = (& $llvmConfig --version).Trim()
  Assert-Condition ($LASTEXITCODE -eq 0 -and $version -eq '23.1.4') "Expected LLVM 23.1.4, found '$version'."
  Assert-Condition (Test-Path (Join-Path $deps 'zlib\lib\zs.lib')) 'Real zlib archive zs.lib is missing.'
  Assert-Condition (Test-Path (Join-Path $deps 'zstd\lib\zstd_static.lib')) 'Real zstd archive zstd_static.lib is missing.'
  New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  $vsDevCmd = Get-VsDevCmd
  $libraryNames = (& $llvmConfig --libnames core analysis irreader nativecodegen passes) -split '\s+' | Where-Object { $_ }
  Assert-Condition ($LASTEXITCODE -eq 0 -and $libraryNames.Count -gt 10) 'llvm-config did not provide the required real LLVM component archives.'
  $response = @(
    "/LIBPATH:`"$(Join-Path $sdk 'lib')`"",
    "/LIBPATH:`"$(Join-Path $deps 'zlib\lib')`"",
    "/LIBPATH:`"$(Join-Path $deps 'zstd\lib')`"",
    'BoundedSLP.obj', 'BoundedSLPDriver.obj'
  ) + $libraryNames + @('zs.lib', 'zstd_static.lib', 'psapi.lib', 'shell32.lib', 'ole32.lib', 'uuid.lib', 'advapi32.lib', 'ws2_32.lib', 'ntdll.lib', 'bcrypt.lib', '/OUT:slp-opt.exe')
  Set-Content -Path (Join-Path $scratch 'driver.rsp') -Value $response

  $repoInclude = Join-Path $repo 'include'
  $sdkInclude = Join-Path $sdk 'include'
  $passSource = Join-Path $repo 'lib\BoundedSLP.cpp'
  $driverSource = Join-Path $repo 'tools\BoundedSLPDriver.cpp'
  $buildScript = @"
@echo off
call "$vsDevCmd" -arch=amd64
if errorlevel 1 exit /b %errorlevel%
cd /d "$scratch"
if errorlevel 1 exit /b %errorlevel%
cl /nologo /c /EHs-c- /GR- /std:c++17 /I "$repoInclude" /I "$sdkInclude" "$passSource" /FoBoundedSLP.obj
if errorlevel 1 exit /b %errorlevel%
cl /nologo /c /EHs-c- /GR- /std:c++17 /I "$repoInclude" /I "$sdkInclude" "$driverSource" /FoBoundedSLPDriver.obj
if errorlevel 1 exit /b %errorlevel%
link @driver.rsp
exit /b %errorlevel%
"@
  $cmdPath = Join-Path $scratch 'build-driver.cmd'
  Set-Content -Path $cmdPath -Value $buildScript -Encoding Ascii
  & cmd.exe /d /c "`"$cmdPath`"" 2>&1 | Tee-Object -FilePath (Join-Path $scratch 'build.log')
  Assert-Condition ($LASTEXITCODE -eq 0 -and (Test-Path $driver)) "Standalone driver build failed with exit code $LASTEXITCODE."
  $result = "LAUNCH_OK $driver LLVM=$version"
  $result | Set-Content -Path (Join-Path $scratch 'launch-result.txt')
  Write-Output $result
}

function Invoke-Doctor {
  $version = (& $llvmConfig --version).Trim()
  Assert-Condition ($LASTEXITCODE -eq 0 -and $version -eq '23.1.4') "Expected LLVM 23.1.4, found '$version'."
  foreach ($tool in @($opt, $llc, $objdump, $llvmConfig, $driver)) {
    Assert-Condition (Test-Path $tool) "Required executable is missing: $tool"
  }
  foreach ($archive in @((Join-Path $deps 'zlib\lib\zs.lib'), (Join-Path $deps 'zstd\lib\zstd_static.lib'))) {
    Assert-Condition (Test-Path $archive) "Required verified dependency archive is missing: $archive"
  }
  $drive = [IO.Path]::GetPathRoot($repo).TrimEnd('\').Substring(0, 1)
  $freeBytes = (Get-PSDrive -Name $drive).Free
  Assert-Condition ($freeBytes -ge 10GB) "Disk reserve below 10 GB on $drive`:."
  $result = "DOCTOR_OK LLVM=$version freeGB=$([math]::Round($freeBytes / 1GB, 2)) driver=$driver"
  New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  $result | Set-Content -Path (Join-Path $scratch 'doctor-result.txt')
  Write-Output $result
}

function Invoke-Drive {
  New-Item -ItemType Directory -Force -Path $scratch | Out-Null
  $input = Join-Path $repo 'test\BoundedSLP.ll'
  $exact = Join-Path $scratch 'BoundedSLP.exact.ll'
  $greedy = Join-Path $scratch 'BoundedSLP.greedy.ll'
  $exactLog = & $driver $input -o $exact 2>&1
  Assert-Condition ($LASTEXITCODE -eq 0) "Exact pass failed: $exactLog"
  $greedyLog = & $driver $input --greedy -o $greedy 2>&1
  Assert-Condition ($LASTEXITCODE -eq 0) "Greedy pass failed: $greedyLog"
  $exactCount = (Select-String -Path $exact -Pattern 'add <2 x i32>' | Measure-Object).Count
  $greedyCount = (Select-String -Path $greedy -Pattern 'add <2 x i32>' | Measure-Object).Count
  Assert-Condition ($exactCount -eq 5 -and $greedyCount -eq 5) "Unexpected vector add counts, exact=$exactCount greedy=$greedyCount."
  $exactText = Get-Content -Raw $exact
  $mismatchBody = [regex]::Match($exactText, '(?ms)^define i32 @mismatched_flags.*?^}')
  $floatBody = [regex]::Match($exactText, '(?ms)^define float @float_not_packed.*?^}')
  Assert-Condition ($mismatchBody.Success -and $mismatchBody.Value -notmatch 'add <2 x i32>') 'Mismatched arithmetic flags were packed.'
  Assert-Condition ($floatBody.Success -and $floatBody.Value -notmatch 'fadd <2 x float>') 'Floating-point instructions were packed despite the integer-only policy.'
  Assert-Condition ((Select-String -Path $exact -Pattern 'load volatile i32' | Measure-Object).Count -eq 4) 'Volatile loads were lost or duplicated.'
  Assert-Condition ($exactText -notmatch 'load <2 x i32>') 'The pass unexpectedly packed memory operations.'
  & $opt -passes=verify -disable-output $exact
  Assert-Condition ($LASTEXITCODE -eq 0) 'LLVM verifier rejected exact output.'
  & $opt -passes=verify -disable-output $greedy
  Assert-Condition ($LASTEXITCODE -eq 0) 'LLVM verifier rejected greedy output.'

  $params = (0..15 | ForEach-Object { "i32 %a$_, i32 %b$_" }) -join ', '
  $ops = (0..15 | ForEach-Object { "  %x$_ = add i32 %a$_, %b$_" }) -join "`n"
  $wide = "define i32 @wide($params) {`n$ops`n  ret i32 %x0`n}`n"
  $wideInput = Join-Path $scratch 'wide16.ll'
  $wideOutput = Join-Path $scratch 'wide16.out.ll'
  Set-Content -Path $wideInput -Value $wide
  $timer = [Diagnostics.Stopwatch]::StartNew()
  & $driver $wideInput -o $wideOutput
  Assert-Condition ($LASTEXITCODE -eq 0) 'The 16-candidate exact-search boundary failed.'
  $timer.Stop()
  & $opt -passes=verify -disable-output $wideOutput
  Assert-Condition ($LASTEXITCODE -eq 0) 'LLVM verifier rejected the 16-candidate result.'
  $wideVectorCount = (Select-String -Path $wideOutput -Pattern 'add <2 x i32>' | Measure-Object).Count
  Assert-Condition ($wideVectorCount -gt 0) 'The 16-candidate block produced no vector operations.'

  $assembly = Join-Path $scratch 'BoundedSLP.s'
  & $llc -O2 -mattr=+sse2 -filetype=asm -o $assembly $exact
  Assert-Condition ($LASTEXITCODE -eq 0) 'LLVM native x86 code generation failed.'
  $nativePackedAdd = Select-String -Path $assembly -Pattern '\bpaddd\b' | Select-Object -First 1
  Assert-Condition ($null -ne $nativePackedAdd) 'Native assembly contains no packed integer add.'
  $nativeObject = Join-Path $scratch 'slp_add2.obj'
  & $llc -O2 -mattr=+sse2 -filetype=obj -o $nativeObject $exact
  Assert-Condition ($LASTEXITCODE -eq 0) 'LLVM native object emission failed.'
  $vsDevCmd = Get-VsDevCmd
  $harnessSource = Join-Path $repo 'test\native_diff.cpp'
  $harnessExe = Join-Path $scratch 'native-diff.exe'
  $nativeCmd = Join-Path $scratch 'build-native.cmd'
  @"
@echo off
call "$vsDevCmd" -arch=amd64
if errorlevel 1 exit /b %errorlevel%
cd /d "$scratch"
if errorlevel 1 exit /b %errorlevel%
cl /nologo /O2 /EHsc /std:c++17 "$harnessSource" "$nativeObject" /Fe:"$harnessExe"
exit /b %errorlevel%
"@ | Set-Content -Path $nativeCmd -Encoding Ascii
  & cmd.exe /d /c "`"$nativeCmd`"" 2>&1 | Tee-Object -FilePath (Join-Path $scratch 'native-build.log')
  Assert-Condition ($LASTEXITCODE -eq 0 -and (Test-Path $harnessExe)) 'Native differential harness build failed.'
  $disassembly = (& $objdump -d (Join-Path $scratch 'native_diff.obj')) -join "`n"
  $scalarBody = [regex]::Match($disassembly, '(?ms)<\?scalar_add2@@.*?>:(.*?retq)')
  Assert-Condition ($scalarBody.Success -and $scalarBody.Value -match '\baddl\b') 'The scalar baseline function was not found in native disassembly.'
  Assert-Condition ($scalarBody.Value -notmatch '\b(padd[a-z]*|addps|addpd|addss|addsd|vadd[a-z]*)\b') 'The scalar baseline contains a packed or vector add.'
  $disassembly | Set-Content -Path (Join-Path $scratch 'native-diff.disasm.txt')
  $nativeResult = & $harnessExe 2>&1
  Assert-Condition ($LASTEXITCODE -eq 0) "Native differential/performance harness failed: $nativeResult"
  $nativeResult | Tee-Object -FilePath (Join-Path $scratch 'native-result.txt')
  $nativeResult | Set-Content -Path (Join-Path $scratch 'drive-result.txt')
  @(
    "command: $driver $input -o $exact",
    "command: $driver $input --greedy -o $greedy",
    "command: $opt -passes=verify -disable-output <each transformed module>",
    "command: $driver $wideInput -o $wideOutput",
    "command: $llc -O2 -mattr=+sse2 -filetype=asm -o $assembly $exact",
    "command: $llc -O2 -mattr=+sse2 -filetype=obj -o $nativeObject $exact",
    "exact vector adds=$exactCount",
    "greedy vector adds=$greedyCount",
    "16-candidate exact-search elapsed_ms=$([math]::Round($timer.Elapsed.TotalMilliseconds, 3)) vector_adds=$wideVectorCount",
    "native packed instruction=$($nativePackedAdd.Line.Trim())",
    'scalar baseline disassembly contains scalar addl and no packed/vector add',
    $nativeResult
  ) | Set-Content -Path (Join-Path $scratch 'drive-result.txt')
  Write-Output "DRIVE_OK exact=$exactCount greedy=$greedyCount boundary16Ms=$([math]::Round($timer.Elapsed.TotalMilliseconds, 3))"
}

function Invoke-Evidence {
  Assert-Condition (Test-Path (Join-Path $scratch 'drive-result.txt')) 'Run Drive before Evidence.'
  New-Item -ItemType Directory -Force -Path $runEvidence | Out-Null
  Copy-Item (Join-Path $scratch 'BoundedSLP.exact.ll') $runEvidence
  Copy-Item (Join-Path $scratch 'BoundedSLP.greedy.ll') $runEvidence
  Copy-Item (Join-Path $repo 'test\BoundedSLP.ll') $runEvidence
  Copy-Item (Join-Path $repo 'test\native_diff.cpp') $runEvidence
  Copy-Item (Join-Path $scratch 'BoundedSLP.s') $runEvidence
  Copy-Item (Join-Path $scratch 'wide16.ll') $runEvidence
  Copy-Item (Join-Path $scratch 'wide16.out.ll') $runEvidence
  Copy-Item (Join-Path $scratch 'drive-result.txt') $runEvidence
  Copy-Item (Join-Path $scratch 'native-result.txt') $runEvidence
  Copy-Item (Join-Path $scratch 'native-build.log') $runEvidence
  Copy-Item (Join-Path $scratch 'native-diff.disasm.txt') $runEvidence
  Copy-Item (Join-Path $scratch 'native_diff.obj') $runEvidence
  Copy-Item (Join-Path $scratch 'build.log') $runEvidence
  Copy-Item (Join-Path $scratch 'launch-result.txt') $runEvidence
  Copy-Item (Join-Path $scratch 'doctor-result.txt') $runEvidence
  Write-Output "EVIDENCE_OK $runEvidence"
}

function Invoke-Cleanup {
  $fullScratch = [IO.Path]::GetFullPath($scratch)
  $fullRepo = [IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'
  Assert-Condition ($fullScratch.StartsWith($fullRepo, [StringComparison]::OrdinalIgnoreCase)) "Refusing cleanup outside repository: $fullScratch"
  if (Test-Path $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
  Write-Output 'CLEANUP_OK build/verify removed; .verify/evidence retained.'
}

switch ($Phase) {
  'Launch' { Invoke-Launch }
  'Doctor' { Invoke-Doctor }
  'Drive' { Invoke-Drive }
  'Evidence' { Invoke-Evidence }
  'Cleanup' { Invoke-Cleanup }
  'All' {
    try {
      Invoke-Launch
      Invoke-Doctor
      Invoke-Drive
      Invoke-Evidence
    } finally {
      Invoke-Cleanup
    }
    Assert-Condition (Test-Path $runEvidence) 'Evidence did not survive cleanup.'
    'CLEANUP_OK build/verify removed; evidence retained.' | Set-Content -Path (Join-Path $runEvidence 'cleanup-result.txt')
    Write-Output "ALL_OK evidence=$runEvidence"
  }
}
