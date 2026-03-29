Param(
    [string]$StartedFile = "started.txt",
    [string]$CompletedFile = "completed.txt",
    [string]$VanSearchExe = "VanSearch.exe",
    [string]$GpuId = "0",
    [string]$OutputFile = "output.txt",
    [int]$Range = 44,
    [string]$StopAddress = "1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU",
    [string[]]$YPrefixes = @("4", "5", "6", "7"),
    [int]$XLength = 6,
    [string]$ZeroSuffix = "00000000000",
    [switch]$UseDatabase,
    [ValidateSet("SqlServer", "Postgres")]
    [string]$DbEngine = "Postgres",
    [string]$DbHost = "YOUR_SERVER_IP",
    [int]$DbPort = 0,
    [string]$DatabaseName = "vandb",
    [string]$DbUser = "",
    [bool]$DbTrustServerCertificate = $true,
    [string]$PostgresOdbcDriver = "{PostgreSQL Unicode}",
    [string]$WorkerId = "",
    [switch]$DbInitSchema,
    [string]$EnvFile = ".env"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

function Import-DotEnv {
    param(
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) {
            return
        }
        $name = $line.Substring(0, $eq).Trim()
        if ($name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            return
        }
        $val = $line.Substring($eq + 1).Trim()
        if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        elseif ($val.Length -ge 2 -and $val.StartsWith("'") -and $val.EndsWith("'")) {
            $val = $val.Substring(1, $val.Length - 2).Replace("''", "'")
        }
        if ($null -eq [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable($name, $val, "Process")
        }
    }
}

Import-DotEnv -Path (Join-Path $scriptDir $EnvFile)

if ($env:VAN_DB_HOST -and $env:VAN_DB_HOST.Trim().Length -gt 0) {
    $DbHost = $env:VAN_DB_HOST.Trim()
}
if ($env:VAN_DB_PORT -and $env:VAN_DB_PORT.Trim().Length -gt 0) {
    $DbPort = [int]$env:VAN_DB_PORT.Trim()
}
if ($env:VAN_DB_NAME -and $env:VAN_DB_NAME.Trim().Length -gt 0) {
    $DatabaseName = $env:VAN_DB_NAME.Trim()
}
if ($env:VAN_DB_USER -and $env:VAN_DB_USER.Trim().Length -gt 0) {
    $DbUser = $env:VAN_DB_USER.Trim()
}
if ($env:DB_ENGINE -in @("Postgres", "SqlServer")) {
    $DbEngine = $env:DB_ENGINE
}

if (-not $WorkerId -or $WorkerId.Trim().Length -eq 0) {
    $WorkerId = $env:COMPUTERNAME
    if (-not $WorkerId) { $WorkerId = "unknown-host" }
}

Write-Host "run_van.ps1: script started" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $VanSearchExe)) {
    Write-Host "File '$VanSearchExe' not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $StartedFile)) {
    New-Item -ItemType File -Path $StartedFile | Out-Null
}

if (-not (Test-Path -LiteralPath $CompletedFile)) {
    New-Item -ItemType File -Path $CompletedFile | Out-Null
}

if ($XLength -ne 6) {
    Write-Host "XLength must be 6 for pattern YXXXXXX + fixed zero tail." -ForegroundColor Red
    exit 1
}

if ($ZeroSuffix -notmatch "^0{11}$") {
    Write-Host "ZeroSuffix must be exactly 11 ASCII '0' characters (pattern YXXXXXX00000000000)." -ForegroundColor Red
    exit 1
}

if (-not $YPrefixes -or $YPrefixes.Count -eq 0) {
    Write-Host "YPrefixes must contain at least one value." -ForegroundColor Red
    exit 1
}

$dbConnString = $null
$script:OdbcConnString = $null
$script:DbEngine = $null

if ($UseDatabase) {
    $dbPassword = $env:VAN_DB_PASSWORD
    if (-not $dbPassword) {
        Write-Host "UseDatabase is set: set VAN_DB_PASSWORD (e.g. in .env next to this script)." -ForegroundColor Red
        exit 1
    }
    if ($DbPort -eq 0) {
        $DbPort = if ($DbEngine -eq "Postgres") { 5432 } else { 1433 }
    }
    if (-not $DbUser -or $DbUser.Trim().Length -eq 0) {
        $DbUser = "vanuser"
    }

    $script:DbEngine = $DbEngine
    try {
        Add-Type -AssemblyName System.Data
    } catch { }

    if ($DbEngine -eq "Postgres") {
        $script:OdbcConnString = "Driver=$PostgresOdbcDriver;Server=$DbHost;Port=$DbPort;Database=$DatabaseName;UID=$DbUser;PWD=$dbPassword;"
        Write-Host "Database engine: PostgreSQL (ODBC) on ${DbHost}:$DbPort, user '$DbUser'." -ForegroundColor DarkGray
    }
    else {
        $trustCert = if ($DbTrustServerCertificate) { "True" } else { "False" }
        $dbConnString = "Server=tcp:${DbHost},${DbPort};Database=${DatabaseName};User ID=${DbUser};Password=${dbPassword};Encrypt=True;TrustServerCertificate=$trustCert;Connection Timeout=30"
        Write-Host "Database engine: SQL Server on ${DbHost}:$DbPort, user '$DbUser'." -ForegroundColor DarkGray
    }
}

function Invoke-DbNonQueryOdbc {
    param(
        [string]$Sql,
        [object[]]$Values = @()
    )
    $cn = New-Object System.Data.Odbc.OdbcConnection($script:OdbcConnString)
    $cn.Open()
    try {
        $cmd = New-Object System.Data.Odbc.OdbcCommand($Sql, $cn)
        foreach ($v in $Values) {
            $null = $cmd.Parameters.Add((New-Object System.Data.Odbc.OdbcParameter("", $v)))
        }
        [void]$cmd.ExecuteNonQuery()
    } finally {
        $cn.Close()
    }
}

function Invoke-DbScalarOdbc {
    param(
        [string]$Sql,
        [object[]]$Values = @()
    )
    $cn = New-Object System.Data.Odbc.OdbcConnection($script:OdbcConnString)
    $cn.Open()
    try {
        $cmd = New-Object System.Data.Odbc.OdbcCommand($Sql, $cn)
        foreach ($v in $Values) {
            $null = $cmd.Parameters.Add((New-Object System.Data.Odbc.OdbcParameter("", $v)))
        }
        return $cmd.ExecuteScalar()
    } finally {
        $cn.Close()
    }
}

function Invoke-DbNonQuery {
    param(
        [string]$Sql,
        [hashtable]$Parameters = @{}
    )
    if ($script:DbEngine -eq "Postgres") {
        throw "Invoke-DbNonQuery: Postgres uses Invoke-DbNonQueryOdbc."
    }
    $cn = New-Object System.Data.SqlClient.SqlConnection($dbConnString)
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $Sql
        foreach ($key in $Parameters.Keys) {
            $p = $cmd.Parameters.AddWithValue($key, $Parameters[$key])
            if ($null -eq $Parameters[$key]) {
                $p.SqlDbType = [System.Data.SqlDbType]::NVarChar
            }
        }
        [void]$cmd.ExecuteNonQuery()
    } finally {
        $cn.Close()
    }
}

function Invoke-DbScalar {
    param(
        [string]$Sql,
        [hashtable]$Parameters = @{}
    )
    if ($script:DbEngine -eq "Postgres") {
        throw "Invoke-DbScalar: Postgres uses Invoke-DbScalarOdbc."
    }
    $cn = New-Object System.Data.SqlClient.SqlConnection($dbConnString)
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $Sql
        foreach ($key in $Parameters.Keys) {
            $null = $cmd.Parameters.AddWithValue($key, $Parameters[$key])
        }
        return $cmd.ExecuteScalar()
    } finally {
        $cn.Close()
    }
}

function Initialize-VanDbSchema {
    if ($script:DbEngine -eq "Postgres") {
        $sql = @"
CREATE TABLE IF NOT EXISTS van_ranges (
    range_key VARCHAR(32) NOT NULL PRIMARY KEY,
    status VARCHAR(20) NOT NULL,
    prefix_index INT NOT NULL DEFAULT 0,
    worker_id VARCHAR(128) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP)
);
"@
        Invoke-DbNonQueryOdbc -Sql $sql
        Invoke-DbNonQueryOdbc -Sql "CREATE INDEX IF NOT EXISTS ix_van_ranges_status ON van_ranges (status)"
        return
    }

    $sql = @"
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'van_ranges' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.van_ranges (
        range_key VARCHAR(32) NOT NULL PRIMARY KEY,
        status NVARCHAR(20) NOT NULL,
        prefix_index INT NOT NULL CONSTRAINT DF_van_ranges_prefix DEFAULT (0),
        worker_id NVARCHAR(128) NOT NULL,
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_van_ranges_updated DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_van_ranges_status ON dbo.van_ranges(status);
END
"@
    Invoke-DbNonQuery -Sql $sql
}

function Get-DbRangeStates {
    if ($script:DbEngine -eq "Postgres") {
        $sql = "SELECT range_key, status, prefix_index, worker_id FROM van_ranges"
        $cn = New-Object System.Data.Odbc.OdbcConnection($script:OdbcConnString)
        $cn.Open()
        try {
            $cmd = New-Object System.Data.Odbc.OdbcCommand($sql, $cn)
            $reader = $cmd.ExecuteReader()
            $rows = @()
            while ($reader.Read()) {
                $rows += [pscustomobject]@{
                    RangeKey    = [string]$reader["range_key"]
                    Status      = [string]$reader["status"]
                    PrefixIndex = [int]$reader["prefix_index"]
                    WorkerId    = [string]$reader["worker_id"]
                }
            }
            $reader.Close()
            return $rows
        } finally {
            $cn.Close()
        }
    }

    $sql = @"
SELECT range_key, status, prefix_index, worker_id
FROM dbo.van_ranges
"@
    $cn = New-Object System.Data.SqlClient.SqlConnection($dbConnString)
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $sql
        $reader = $cmd.ExecuteReader()
        $rows = @()
        while ($reader.Read()) {
            $rows += [pscustomobject]@{
                RangeKey    = [string]$reader["range_key"]
                Status      = [string]$reader["status"]
                PrefixIndex = [int]$reader["prefix_index"]
                WorkerId    = [string]$reader["worker_id"]
            }
        }
        $reader.Close()
        return $rows
    } finally {
        $cn.Close()
    }
}

function Try-DbClaimRangeKey {
    param(
        [string]$RangeKey,
        [int]$PrefixIndex = 0
    )
    $RangeKey = $RangeKey.ToUpperInvariant()
    if ($script:DbEngine -eq "Postgres") {
        $sql = "INSERT INTO van_ranges (range_key, status, prefix_index, worker_id) VALUES (?,?,?,?)"
        try {
            Invoke-DbNonQueryOdbc -Sql $sql -Values @($RangeKey, "in_progress", $PrefixIndex, $WorkerId)
            return $true
        } catch {
            return $false
        }
    }

    $sql = @"
INSERT INTO dbo.van_ranges (range_key, status, prefix_index, worker_id)
VALUES (@range_key, N'in_progress', @prefix_index, @worker_id)
"@
    try {
        Invoke-DbNonQuery -Sql $sql -Parameters @{
            "@range_key"   = $RangeKey
            "@prefix_index" = $PrefixIndex
            "@worker_id"   = $WorkerId
        }
        return $true
    } catch {
        return $false
    }
}

function Update-DbPrefixIndex {
    param(
        [string]$RangeKey,
        [int]$PrefixIndex
    )
    $RangeKey = $RangeKey.ToUpperInvariant()
    if ($script:DbEngine -eq "Postgres") {
        $sql = "UPDATE van_ranges SET prefix_index = ?, updated_at = CURRENT_TIMESTAMP WHERE range_key = ? AND worker_id = ?"
        Invoke-DbNonQueryOdbc -Sql $sql -Values @($PrefixIndex, $RangeKey, $WorkerId)
        return
    }

    $sql = @"
UPDATE dbo.van_ranges
SET prefix_index = @prefix_index, updated_at = SYSUTCDATETIME()
WHERE range_key = @range_key AND worker_id = @worker_id
"@
    Invoke-DbNonQuery -Sql $sql -Parameters @{
        "@range_key"    = $RangeKey
        "@prefix_index" = $PrefixIndex
        "@worker_id"    = $WorkerId
    }
}

function Complete-DbRangeKey {
    param([string]$RangeKey)
    $RangeKey = $RangeKey.ToUpperInvariant()
    if ($script:DbEngine -eq "Postgres") {
        $sql = "UPDATE van_ranges SET status = 'completed', updated_at = CURRENT_TIMESTAMP WHERE range_key = ? AND worker_id = ?"
        Invoke-DbNonQueryOdbc -Sql $sql -Values @($RangeKey, $WorkerId)
        return
    }

    $sql = @"
UPDATE dbo.van_ranges
SET status = N'completed', updated_at = SYSUTCDATETIME()
WHERE range_key = @range_key AND worker_id = @worker_id
"@
    Invoke-DbNonQuery -Sql $sql -Parameters @{
        "@range_key" = $RangeKey
        "@worker_id" = $WorkerId
    }
}

function Merge-DbIntoMaps {
    param(
        [hashtable]$CompletedMap,
        [hashtable]$BlockedByOthers
    )
    $rows = Get-DbRangeStates
    foreach ($r in $rows) {
        $k = $r.RangeKey.ToUpperInvariant()
        if ($r.Status -eq "completed") {
            $CompletedMap[$k] = $true
        }
        elseif ($r.Status -eq "in_progress" -and $r.WorkerId -ne $WorkerId) {
            $BlockedByOthers[$k] = $true
        }
    }
}

function Test-CanResumeFromDb {
    param([string]$RangeKey)
    $RangeKey = $RangeKey.ToUpperInvariant()
    if ($script:DbEngine -eq "Postgres") {
        $sql = "SELECT 1 FROM van_ranges WHERE range_key = ? AND worker_id = ? AND status = 'in_progress' LIMIT 1"
        $one = Invoke-DbScalarOdbc -Sql $sql -Values @($RangeKey, $WorkerId)
        return ($null -ne $one -and [DBNull]::Value -ne $one)
    }

    $sql = @"
SELECT 1 FROM dbo.van_ranges
WHERE range_key = @range_key AND worker_id = @worker_id AND status = N'in_progress'
"@
    $one = Invoke-DbScalar -Sql $sql -Parameters @{
        "@range_key" = $RangeKey
        "@worker_id" = $WorkerId
    }
    return ($null -ne $one)
}

function Get-RandomHexString {
    param(
        [int]$Length
    )
    $hex = "0123456789ABCDEF".ToCharArray()
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        [void]$sb.Append($hex[(Get-Random -Minimum 0 -Maximum 16)])
    }
    return $sb.ToString()
}

function Get-CompletedMap {
    param(
        [string]$Path
    )
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path |
            ForEach-Object {
                $value = $_.Trim().ToUpperInvariant()
                if ($value -match "^[0-9A-F]+$") {
                    $map[$value] = $true
                }
            }
    }
    return $map
}

function Get-StartedState {
    param(
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "\S" } | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    $line = $line.Trim().ToUpperInvariant()
    if ($line -match "^([0-9A-F]+)\|(\d+)$") {
        return @{
            RandomX = $matches[1]
            PrefixIndex = [int]$matches[2]
        }
    }

    # Backward compatibility with old format: only combination value.
    if ($line -match "^[0-9A-F]+$") {
        return @{
            RandomX = $line
            PrefixIndex = 0
        }
    }

    return $null
}

$completedMap = Get-CompletedMap -Path $CompletedFile
if ($null -eq $completedMap) {
    $completedMap = @{}
}

$blockedByOthers = @{}
if ($UseDatabase) {
    if ($DbInitSchema) {
        Initialize-VanDbSchema
        Write-Host "Database: schema verified/created." -ForegroundColor DarkGray
    }
    try {
        Merge-DbIntoMaps -CompletedMap $completedMap -BlockedByOthers $blockedByOthers
    } catch {
        Write-Host "Database error while loading ranges: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host "Database: host $DbHost; worker '$WorkerId'; completed keys (file+DB): $($completedMap.Count); in progress elsewhere: $($blockedByOthers.Count)" -ForegroundColor DarkGray
}

Write-Host "Loaded completed X-sequences: $($completedMap.Count)" -ForegroundColor DarkGray
Write-Host "Pattern: Y + $XLength random hex + $ZeroSuffix (YXXXXXX00000000000). Y order: $($YPrefixes -join ', ')." -ForegroundColor DarkGray

$found = $false
while (-not $found) {
    $state = Get-StartedState -Path $StartedFile
    $randomX = $null
    $startPrefixIndex = 0

    $canResume = $false
    if ($state -and $state.RandomX.Length -eq $XLength -and -not $completedMap.ContainsKey($state.RandomX)) {
        $canResume = $true
        if ($UseDatabase -and $blockedByOthers.ContainsKey($state.RandomX)) {
            Write-Host "Started key $($state.RandomX) is in progress on another worker. Clearing started file." -ForegroundColor Yellow
            Clear-Content -LiteralPath $StartedFile
            $canResume = $false
        }
        elseif ($UseDatabase -and -not (Test-CanResumeFromDb -RangeKey $state.RandomX)) {
            $prefixIdx = [Math]::Max(0, [Math]::Min($state.PrefixIndex, $YPrefixes.Count - 1))
            if (-not (Try-DbClaimRangeKey -RangeKey $state.RandomX -PrefixIndex $prefixIdx)) {
                Write-Host "Could not reserve $($state.RandomX) in DB (already taken). Clearing started file." -ForegroundColor Yellow
                Clear-Content -LiteralPath $StartedFile
                $canResume = $false
            }
        }
    }

    if ($canResume) {
        $randomX = $state.RandomX
        $startPrefixIndex = [Math]::Max(0, [Math]::Min($state.PrefixIndex, $YPrefixes.Count - 1))
        Write-Host "Resuming X-sequence $randomX from Y-index $startPrefixIndex." -ForegroundColor Cyan
    } else {
        Write-Host "Generating new random X-sequence..." -ForegroundColor Gray
        $attempts = 0
        $maxAttempts = 1000000
        while ($attempts -lt $maxAttempts) {
            $candidate = (Get-RandomHexString -Length $XLength).ToUpperInvariant()
            if ($completedMap.ContainsKey($candidate)) {
                $attempts++
                continue
            }
            if ($blockedByOthers.ContainsKey($candidate)) {
                $attempts++
                continue
            }
            if ($UseDatabase) {
                if (-not (Try-DbClaimRangeKey -RangeKey $candidate -PrefixIndex 0)) {
                    $attempts++
                    continue
                }
            }
            $randomX = $candidate
            Write-Host "Picked new X-sequence: $randomX" -ForegroundColor Cyan
            break
        }

        if (-not $randomX) {
            Write-Host "Could not generate new X-sequence not present in completed list. Stopping." -ForegroundColor Yellow
            break
        }
    }

    for ($prefixIndex = $startPrefixIndex; $prefixIndex -lt $YPrefixes.Count; $prefixIndex++) {
        $y = $YPrefixes[$prefixIndex].Trim().ToUpperInvariant()
        if ($y.Length -ne 1 -or $y -notmatch "^[0-9A-F]$") {
            Write-Host "Skipping invalid Y prefix '$y'." -ForegroundColor DarkYellow
            continue
        }

        $startString = "$y$randomX$ZeroSuffix"
        Set-Content -LiteralPath $StartedFile -Value "$randomX|$prefixIndex" -Encoding UTF8
        if ($UseDatabase) {
            Update-DbPrefixIndex -RangeKey $randomX -PrefixIndex $prefixIndex
        }

        $beforeLength = -1
        if (Test-Path -LiteralPath $OutputFile) {
            $beforeLength = (Get-Item -LiteralPath $OutputFile).Length
        }

        $arguments = @(
            "-gpuId", $GpuId,
            "-start", $startString,
            "-o", $OutputFile,
            "-range", $Range,
            "-stop", $StopAddress
        )

        Write-Host "Starting process: $VanSearchExe $($arguments -join ' ')" -ForegroundColor DarkCyan
        & ".\${VanSearchExe}" @arguments

        if ($LASTEXITCODE -ne 0) {
            Write-Host "VanSearch exited with code $LASTEXITCODE." -ForegroundColor DarkYellow
        } else {
            Write-Host "VanSearch finished with exit code 0." -ForegroundColor Green
        }

        $afterLength = $beforeLength
        if (Test-Path -LiteralPath $OutputFile) {
            $afterLength = (Get-Item -LiteralPath $OutputFile).Length
        }

        if (($beforeLength -lt 0 -and $afterLength -ge 0) -or ($afterLength -gt $beforeLength)) {
            Write-Host "Output file changed. Assuming target match was found. Stopping search." -ForegroundColor Green
            if ($UseDatabase) {
                Complete-DbRangeKey -RangeKey $randomX
            }
            $found = $true
            break
        }
    }

    if ($found) {
        Clear-Content -LiteralPath $StartedFile
        break
    }

    Add-Content -LiteralPath $CompletedFile -Value $randomX
    $completedMap[$randomX] = $true
    if ($UseDatabase) {
        Complete-DbRangeKey -RangeKey $randomX
    }
    Clear-Content -LiteralPath $StartedFile
    Write-Host "Completed full Y-cycle for X-sequence $randomX. Moving to next random X..." -ForegroundColor Gray
}

Write-Host "Script finished." -ForegroundColor Cyan


