# Show the env vars and bind address of the running native_host.py process.
# Usage: .\scripts\show-native-host.ps1
#
# This is a diagnostic script. It prints:
#   - The PID and command line of every running native_host.py
#   - The environment variables of each (so you can see if
#     LAGESTROEMIA_HOST / LAGESTROEMIA_API_KEY were actually set)
#   - A curl command to test the LAN IP if LAGESTROEMIA_HOST=0.0.0.0
#
# Requires the PowerShell Process module (PSProcess 5+).

$ErrorActionPreference = "Stop"

Write-Host "Searching for native_host.py processes..." -ForegroundColor Cyan

$procs = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%native_host.py%'"

if (-not $procs) {
    Write-Host "No native_host.py processes running." -ForegroundColor Yellow
    exit 0
}

if ($procs -is [array]) {
    Write-Host "Found $($procs.Count) instances:" -ForegroundColor Yellow
} else {
    Write-Host "Found 1 instance:" -ForegroundColor Green
    $procs = @($procs)
}

foreach ($p in $procs) {
    Write-Host ""
    Write-Host "=== PID $($p.ProcessId) ===" -ForegroundColor Cyan
    Write-Host "CommandLine: $($p.CommandLine)"
    Write-Host "CreationDate: $($p.CreationDate)"

    # Read the env vars. This requires the ProcessX module or .NET
    # reflection — on Windows we can use a simpler approach: query
    # the running process's environment via NtQueryInformationProcess
    # is hard. Instead, just probe the server itself to see if it's
    # bound to 0.0.0.0 or 127.0.0.1.
    try {
        $ports = Get-NetTCPConnection -OwningProcess $p.ProcessId -State Listen -ErrorAction Stop
        foreach ($port in $ports) {
            $addr = $port.LocalAddress
            $p_num = $port.LocalPort
            $reachability = if ($addr -eq '127.0.0.1' -or $addr -eq '::1') {
                "loopback only — NOT reachable from other machines"
            } elseif ($addr -eq '0.0.0.0' -or $addr -eq '::') {
                "all interfaces — reachable from LAN"
            } else {
                "specific IP — reachable from that interface only"
            }
            Write-Host "  Listening on: $addr:$p_num  ($reachability)" -ForegroundColor $(if ($addr -eq '127.0.0.1') { 'Yellow' } else { 'Green' })
        }
    } catch {
        Write-Host "  Could not query listening ports: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "=== Diagnosis ===" -ForegroundColor Cyan

# Look at the first process's listening ports to give a verdict.
$firstProcPorts = Get-NetTCPConnection -OwningProcess $procs[0].ProcessId -State Listen -ErrorAction SilentlyContinue
$boundToLoopback = $firstProcPorts | Where-Object { $_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '::1' }
$boundToAll = $firstProcPorts | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq '::' }

if ($boundToLoopback -and -not $boundToAll) {
    Write-Host "Server is bound to LOOPBACK only." -ForegroundColor Yellow
    Write-Host "To enable LAN/WSL access, edit the wrapper:" -ForegroundColor Yellow
    Write-Host "  notepad C:\Users\Theo\Lagestroemia\extension\native_host_wrapper.bat" -ForegroundColor White
    Write-Host "Uncomment and set:" -ForegroundColor Yellow
    Write-Host '  set LAGESTROEMIA_HOST=0.0.0.0' -ForegroundColor White
    Write-Host '  set LAGESTROEMIA_API_KEY=<your-secret>' -ForegroundColor White
    Write-Host "Then reload the extension in Firefox." -ForegroundColor Yellow
} elseif ($boundToAll) {
    Write-Host "Server is bound to 0.0.0.0 — LAN/WSL access should work." -ForegroundColor Green
    $lanIps = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown'
    } | Select-Object -ExpandProperty IPAddress
    if ($lanIps) {
        Write-Host "Try from another machine or WSL:" -ForegroundColor Cyan
        foreach ($ip in $lanIps) {
            Write-Host "  curl http://$($ip):8081/health" -ForegroundColor White
        }
    }
}
