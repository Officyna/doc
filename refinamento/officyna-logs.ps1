<#
.SYNOPSIS
    Menu interativo para visualização formatada e colorida dos logs dos microsserviços Officyna (EKS / Docker).
#>

$Namespace = "officyna"
$ClusterName = "eks-officyna-service"
$Region = "us-east-1"

function Format-OfficynaLogLine {
    param(
        [string]$RawLine,
        [switch]$Compact
    )

    if ($RawLine -match '^\[pod/([^/]+)/[^\]]+\]\s*(\{.*\})$') {
        $svc = $matches[1] -replace '-[a-z0-9]{8,10}-[a-z0-9]{5}$', ''
        try {
            $log = $matches[2] | ConvertFrom-Json
            $time = ([datetime]$log.'@timestamp').ToString("HH:mm:ss.fff")
            $level = "$($log.level)".PadRight(5)
            $corr = if ($log.correlationId) {
                $len = [Math]::Min(8, $log.correlationId.Length)
                $log.correlationId.Substring(0, $len)
            } else {
                "--------"
            }

            $color = switch ($log.level) {
                "ERROR" { "Red" }
                "WARN"  { "Yellow" }
                default {
                    switch -Wildcard ($svc) {
                        "*os*"         { "Cyan" }
                        "*production*" { "Green" }
                        "*billing*"    { "Magenta" }
                        "*users*"      { "Blue" }
                        default        { "White" }
                    }
                }
            }

            if ($Compact) {
                Write-Host "$time [$svc] | $level | ($corr) -> $($log.message)" -ForegroundColor $color
            } else {
                Write-Host "$time | $($svc.PadRight(28)) | $level | [$corr] | $($log.message)" -ForegroundColor $color
            }
        } catch {
            Write-Host $RawLine
        }
    } elseif ($RawLine -match '^\s*(\{.*\})\s*$') {
        try {
            $log = $matches[1] | ConvertFrom-Json
            $time = ([datetime]$log.'@timestamp').ToString("HH:mm:ss.fff")
            $level = "$($log.level)".PadRight(5)
            $corr = if ($log.correlationId) {
                $len = [Math]::Min(8, $log.correlationId.Length)
                $log.correlationId.Substring(0, $len)
            } else {
                "--------"
            }
            $color = switch ($log.level) {
                "ERROR" { "Red" }
                "WARN"  { "Yellow" }
                default { "Cyan" }
            }
            Write-Host "$time | $level | [$corr] | $($log.message)" -ForegroundColor $color
        } catch {
            Write-Host $RawLine
        }
    } else {
        Write-Host $RawLine -ForegroundColor DarkGray
    }
}

function Show-Header {
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "          OFFICYNA - CENTRAL DE LOGS E EVENTOS (SAGA)           " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Legenda: " -NoNewline
    Write-Host "[os-service] " -ForegroundColor Cyan -NoNewline
    Write-Host "[production] " -ForegroundColor Green -NoNewline
    Write-Host "[billing] " -ForegroundColor Magenta -NoNewline
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host "[ERROR]" -ForegroundColor Red
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "1. Todos os logs de todos os serviços em tempo real (EKS)"
    Write-Host "2. Apenas Eventos SQS / SNS / SAGA em tempo real (Versão enxuta)"
    Write-Host "3. Rastrear fluxo de uma O.S. por correlationId ou serviceOrderId"
    Write-Host "4. Apenas Erros e Avisos (ERROR / WARN) de todos os serviços"
    Write-Host "5. Logs de um microsserviço específico (os / production / billing / users)"
    Write-Host "6. Atualizar kubeconfig da AWS (aws eks update-kubeconfig) e listar pods"
    Write-Host "7. Logs locais via Docker Compose ( Eventos / correlationId )"
    Write-Host "0. Sair"
    Write-Host "================================================================" -ForegroundColor Cyan
}

while ($true) {
    Show-Header
    $choice = Read-Host "Escolha uma opção (0-7)"

    switch ($choice) {
        "1" {
            Write-Host "`nIniciando stream de todos os serviços (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
            kubectl logs -f -l app.kubernetes.io/component=api -n $Namespace --prefix=true --tail=100 --max-log-requests=10 | ForEach-Object {
                Format-OfficynaLogLine -RawLine $_
            }
            Pause
        }
        "2" {
            Write-Host "`nMonitorando Eventos SQS / SNS / SAGA (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
            kubectl logs -f -l app.kubernetes.io/component=api -n $Namespace --prefix=true --tail=200 --max-log-requests=10 |
                Select-String -Pattern "event|topic|SQS|status=" | ForEach-Object {
                    Format-OfficynaLogLine -RawLine $_.Line -Compact
                }
            Pause
        }
        "3" {
            $searchId = Read-Host "`nDigite o correlationId ou serviceOrderId"
            if (-not [string]::IsNullOrWhiteSpace($searchId)) {
                Write-Host "`nRastreando '$searchId' em todos os serviços (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
                kubectl logs -f -l app.kubernetes.io/component=api -n $Namespace --prefix=true --tail=1000 --max-log-requests=10 |
                    Select-String -Pattern ([regex]::Escape($searchId)) | ForEach-Object {
                        Format-OfficynaLogLine -RawLine $_.Line -Compact
                    }
            }
            Pause
        }
        "4" {
            Write-Host "`nMonitorando apenas WARN e ERROR em todos os serviços (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
            kubectl logs -f -l app.kubernetes.io/component=api -n $Namespace --prefix=true --tail=300 --max-log-requests=10 |
                Select-String -Pattern '"level":"(ERROR|WARN)"' | ForEach-Object {
                    Format-OfficynaLogLine -RawLine $_.Line -Compact
                }
            Pause
        }
        "5" {
            Write-Host "`nPods disponíveis no namespace '$Namespace':" -ForegroundColor Cyan
            kubectl get pods -n $Namespace
            $svcFilter = Read-Host "`nDigite parte do nome do serviço (ex: os, production, billing, users)"
            if (-not [string]::IsNullOrWhiteSpace($svcFilter)) {
                Write-Host "`nExibindo logs para '*$svcFilter*' (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
                kubectl logs -f -l app.kubernetes.io/component=api -n $Namespace --prefix=true --tail=200 --max-log-requests=10 |
                    Where-Object { $_ -match "^\[pod/[^/]*$svcFilter" } | ForEach-Object {
                        Format-OfficynaLogLine -RawLine $_ -Compact
                    }
            }
            Pause
        }
        "6" {
            Write-Host "`nAtualizando kubeconfig para o cluster '$ClusterName' ($Region)..." -ForegroundColor Cyan
            aws eks update-kubeconfig --region $Region --name $ClusterName
            Write-Host "`nPods no namespace '$Namespace':" -ForegroundColor Cyan
            kubectl get pods -n $Namespace -o wide
            Pause
        }
        "7" {
            Write-Host "`nMonitorando Docker Compose local (Pressione Ctrl+C para parar)...`n" -ForegroundColor Yellow
            docker compose logs -f | Select-String -Pattern "event|topic|correlationId"
            Pause
        }
        "0" {
            Write-Host "Encerrando..." -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "Opção inválida!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

