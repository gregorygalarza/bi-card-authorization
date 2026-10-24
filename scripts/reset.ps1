$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Warning "Esto eliminará el volumen PostgreSQL y TODOS los datos locales."
$answer = Read-Host "Escribe RESET para continuar"

if ($answer -ne "RESET") {
    Write-Host "Operación cancelada."
    exit 0
}

docker compose down -v
