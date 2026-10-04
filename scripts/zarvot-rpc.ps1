[CmdletBinding()]
param(
    [string]$Method = 'tools/list',
    [string]$Tool,
    [string]$ArgumentsJson = '{}',
    [int]$Port = 9742,
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$request = @{ jsonrpc = '2.0'; id = 1; method = $Method }
if ($Tool) {
    $request.method = 'tools/call'
    $request.params = @{ name = $Tool; arguments = ($ArgumentsJson | ConvertFrom-Json) }
}
$client = [Net.Sockets.TcpClient]::new()
try {
    if (-not $client.ConnectAsync('127.0.0.1', $Port).Wait(5000)) {
        throw "Emulator connection timed out on port $Port"
    }
    $stream = $client.GetStream()
    $stream.ReadTimeout = $TimeoutSeconds * 1000
    $stream.WriteTimeout = $TimeoutSeconds * 1000
    $bytes = [Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Depth 30 -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $buffer = [byte[]]::new(65536)
    $response = [IO.MemoryStream]::new()
    try {
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $response.Write($buffer, 0, $count)
            $json = [Text.Encoding]::UTF8.GetString($response.ToArray())
            try { $parsed = $json | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($parsed.error) { throw ($parsed.error | ConvertTo-Json -Compress) }
            return $parsed
        }
        throw 'Emulator closed the connection before returning a complete response'
    } finally { $response.Dispose() }
} finally { $client.Dispose() }
