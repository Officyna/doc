# Visualização de Logs dos Eventos de Todos os Serviços

Todos os microsserviços do **Officyna** escrevem logs estruturados em JSON no `stdout` via `logback-spring.xml` contendo o campo `correlationId` (propagado tanto via HTTP header `X-Correlation-Id` quanto nos `messageAttributes` do SQS).

## Atalho: Script Interativo Automatizado (`officyna-logs.ps1`)

Para abrir o menu interativo com todas as opções prontas (logs gerais, eventos SAGA, busca por `correlationId`/`serviceOrderId`, erros e atualização do `kubeconfig`), execute no PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "c:\desnv\intelij-workspace\officyna\doc\refinamento\officyna-logs.ps1"
```

---

Você também pode visualizar os logs manualmente de 3 formas, dependendo de onde está rodando:

---

## 1. No Kubernetes (EKS) — Tempo real via terminal (`kubectl`)

Antes de consultar os logs, certifique-se de que o `kubeconfig` local está apontando para o cluster EKS atual:

```powershell
aws eks update-kubeconfig --region us-east-1 --name eks-officyna-service
```

Como todos os serviços rodam no namespace `officyna` (veja `deployment.yaml`), você pode acompanhar os logs de **todos os pods simultaneamente** com um único comando:

```powershell
# Acompanhar os logs de todos os microsserviços do namespace officyna ao vivo
kubectl logs -f -l app.kubernetes.io/component=api -n officyna --prefix=true --max-log-requests=10
```

- **Filtrar apenas logs de eventos SQS/SNS de todos os serviços**:
  ```powershell
  kubectl logs -f -l app.kubernetes.io/component=api -n officyna --prefix=true --max-log-requests=10 | Select-String -Pattern "event|topic|SQS|correlationId"
  ```

- **Rastrear o fluxo completo (SAGA) de uma única O.S. ponta a ponta pelo `correlationId` ou `serviceOrderId` (formatado e colorido por serviço)**:
  ```powershell
  $id = "SEU_CORRELATION_ID_OU_OS_ID"
  kubectl logs -f -l app.kubernetes.io/component=api -n officyna --prefix=true --tail=500 --max-log-requests=10 | Select-String -Pattern $id | ForEach-Object {
      if ($_.Line -match '^\[pod/([^/]+)/[^\]]+\]\s*(\{.*\})$') {
          $svc = $matches[1] -replace '-[a-z0-9]{8,10}-[a-z0-9]{5}$', ''
          try {
              $log = $matches[2] | ConvertFrom-Json
              $time = ([datetime]$log.'@timestamp').ToString("HH:mm:ss.fff")
              $level = $log.level.PadRight(5)
              $corr = if ($log.correlationId) { $log.correlationId.Substring(0,8) } else { "--------" }
              $color = switch ($log.level) {
                  "ERROR" { "Red" }
                  "WARN"  { "Yellow" }
                  default {
                      switch -Wildcard ($svc) {
                          "*os*"         { "Cyan" }
                          "*production*" { "Green" }
                          "*billing*"    { "Magenta" }
                          default        { "White" }
                      }
                  }
              }
              Write-Host "$time [$svc] | $level | ($corr) -> $($log.message)" -ForegroundColor $color
          } catch {
              Write-Host $_.Line
          }
      }
  }
  ```

### Visualização Formatada e Colorida no PowerShell (JSON Pretty Print)

Como os serviços emitem logs em JSON (`LogstashEncoder`), o comando abaixo extrai apenas os campos importantes (`@timestamp`, `serviço`, `level`, `correlationId` e `message`) e colore cada serviço e nível de log no terminal:

```powershell
kubectl logs -f -l app.kubernetes.io/component=api -n officyna --prefix=true --max-log-requests=10 | ForEach-Object {
    if ($_ -match '^\[pod/([^/]+)/[^\]]+\]\s*(\{.*\})$') {
        $pod = $matches[1] -replace '-[a-z0-9]{8,10}-[a-z0-9]{5}$', ''
        try {
            $log = $matches[2] | ConvertFrom-Json
            $time = ([datetime]$log.'@timestamp').ToString("HH:mm:ss.fff")
            $level = $log.level.PadRight(5)
            $corr = if ($log.correlationId) { "[$($log.correlationId.Substring(0,8))]" } else { "[--------]" }
            $color = switch ($log.level) {
                "ERROR" { "Red" }
                "WARN"  { "Yellow" }
                default {
                    switch -Wildcard ($pod) {
                        "*os*"         { "Cyan" }
                        "*production*" { "Green" }
                        "*billing*"    { "Magenta" }
                        default        { "White" }
                    }
                }
            }
            Write-Host "$time | $($pod.PadRight(28)) | $level | $corr | $($log.message)" -ForegroundColor $color
        } catch {
            Write-Host $_
        }
    }
}
```

**Exemplo de saída no console:**
```text
16:52:10.124 | officyna-os-service          | INFO  | [a4e0ba7b] | Mensagem enviada para a fila SQS eventForDiagnostics: id=os-123
16:52:10.450 | officyna-production-service  | INFO  | [a4e0ba7b] | Recebida(s) 1 mensagem(ns) da fila SQS: eventForDiagnostics
16:52:14.890 | officyna-billing-service     | INFO  | [a4e0ba7b] | Publicando eventBugetGenerated para serviceOrderId=os-123
```
*(Legenda de cores: `os-service` em **ciano**, `production-service` em **verde**, `billing-service` em **magenta**, `WARN` em **amarelo** e `ERROR` em **vermelho**).*

- **Versão enxuta focada apenas nos Eventos / SAGA (formatada e colorida por serviço)**:
```powershell
kubectl logs -f -l app.kubernetes.io/component=api -n officyna --prefix=true --max-log-requests=10 | Select-String -Pattern "event|topic|SQS|status=" | ForEach-Object {
    if ($_.Line -match '^\[pod/([^/]+)/[^\]]+\]\s*(\{.*\})$') {
        $svc = $matches[1] -replace '-[a-z0-9]{8,10}-[a-z0-9]{5}$', ''
        try {
            $log = $matches[2] | ConvertFrom-Json
            $time = ([datetime]$log.'@timestamp').ToString("HH:mm:ss.fff")
            $level = $log.level.PadRight(5)
            $corr = if ($log.correlationId) { $log.correlationId.Substring(0,8) } else { "--------" }
            $color = switch ($log.level) {
                "ERROR" { "Red" }
                "WARN"  { "Yellow" }
                default {
                    switch -Wildcard ($svc) {
                        "*os*"         { "Cyan" }
                        "*production*" { "Green" }
                        "*billing*"    { "Magenta" }
                        default        { "White" }
                    }
                }
            }
            Write-Host "$time [$svc] | $level | ($corr) -> $($log.message)" -ForegroundColor $color
        } catch {
            Write-Host $_.Line
        }
    }
}
```

---

## 2. No New Relic (Observabilidade do Cluster)

Na infraestrutura do cluster (`newrelic.tf`), está instalado o chart `nri-bundle`.
Para visualizar e pesquisar os logs JSON (por `correlationId`, `serviceOrderId`, etc.) diretamente na aba **Logs** do painel do **New Relic**, habilite o encaminhamento de logs no `newrelic.tf`:

```hcl
set {
  name  = "logging.enabled"
  value = "true"
}
```

Com isso, no New Relic Logs é possível filtrar por `correlationId:"<uuid>"` e visualizar a linha do tempo completa passando por `os-service`, `production-service` e `billing-service`.

---

## 3. Localmente (Docker Compose)

Se estiver rodando os containers localmente:

```powershell
docker compose logs -f | Select-String -Pattern "event|topic|correlationId"
```

