# RFCs e ADRs: Infraestrutura em Nuvem e Arquitetura Serverless
**Projeto: Tech Challenge - Fase 3**  
**Escopo: Gestão de Ordens de Serviço (OS) em Oficina Mecânica**  
**Autor: Equipe de Arquitetura (SOAT)**  
**Status: Aprovado**

---

## 📑 ÍNDICE
1. [RFC 001: Escolha do Provedor de Nuvem (AWS)](#rfc-001-escolha-do-provedor-de-nuvem-aws)
2. [RFC 002: Escolha do Banco de Dados (Amazon DocumentDB)](#rfc-002-escolha-do-banco-de-dados-amazon-documentdb)
3. [RFC 003: Estratégia de Autenticação (JWT, Kong Gateway e AWS Lambda em Java)](#rfc-003-estrategia-de-autenticacao-jwt-kong-gateway-e-aws-lambda-em-java)
4. [ADR 001: Padrão de Comunicação (REST APIs via API Gateway)](#adr-001-padrao-de-comunicacao-rest-apis-via-api-gateway)
5. [ADR 002: Escalabilidade Automática com HPA no Amazon EKS](#adr-002-escalabilidade-automatica-com-hpa-no-amazon-eks)

---

# RFCs (Request for Comments)

## RFC 001: Escolha do Provedor de Nuvem (AWS)

### 1. Contexto e Problema
A oficina mecânica está expandindo suas operações para múltiplas unidades físicas. Com o aumento expressivo no volume de clientes, veículos cadastrados e Ordens de Serviço (OS), a arquitetura local ou monolítica anterior tornou-se obsoleta. Precisamos migrar para um ambiente em nuvem que ofereça:
*   **Alta Disponibilidade (HA):** Tolerância a falhas com distribuição geográfica (Multi-AZ).
*   **Escalabilidade Elástica:** Capacidade de absorver picos de demanda (ex: abertura de OS em horários de pico comercial) e reduzir custos em momentos de ociosidade.
*   **Ecosystem Serverless e Containerizado:** Suporte nativo a clusters Kubernetes gerenciados e funções sob demanda para lógica de autenticação rápida.

### 2. Proposta Técnica (AWS - Amazon Web Services)
A adoção da **AWS** como nuvem principal do projeto baseia-se na maturidade dos seus serviços gerenciados, garantindo que o foco do time de engenharia seja no desenvolvimento de regras de negócio (gestão de oficinas) e não na administração física da infraestrutura.

Os pilares da infraestrutura na AWS serão compostos por:
*   **Amazon EKS (Elastic Kubernetes Service):** Para orquestração da aplicação principal (Java), provendo alta disponibilidade nativa do plano de controle.
*   **AWS Lambda:** Para execução serverless da lógica de validação de CPF e emissão de tokens JWT, otimizando custos (modelo pay-per-use).
*   **Amazon DocumentDB:** Banco de dados NoSQL gerenciado de documentos com total compatibilidade com MongoDB.
*   **VPC (Virtual Private Cloud):** Segmentação de rede rígida com sub-redes públicas para o Gateway de entrada e privadas para o banco de dados e workloads do EKS.

### 3. Alternativas Consideradas
*   **GCP (Google Cloud Platform):** Excelente oferta de Kubernetes (GKE), mas apresenta serviços de banco de dados orientados a documentos gerenciados de forma proprietária (Firestore), que limitam a portabilidade quando comparados com a compatibilidade MongoDB do DocumentDB.
*   **Microsoft Azure:** Possui o AKS e o Cosmos DB (com API para Mongo), porém o custo total de propriedade (TCO) para a combinação de funções serverless em Java e banco gerenciado mostrou-se ligeiramente superior ao modelo da AWS, além da familiaridade técnica prévia do time com a AWS.

### 4. Análise de Prós e Contras (AWS)
*   **Prós:**
    *   **Maturidade do Kubernetes (EKS):** O EKS oferece um plano de controle robusto e SLA de 99.95%, integrando-se nativamente com o IAM para autenticação e RBAC.
    *   **Desempenho Serverless com Java no Lambda:** Uso de recursos como *SnapStart* para reduzir o Cold Start típico de aplicações Java na nuvem.
    *   **Segurança de Ponta a Ponta:** Integração nativa de criptografia via AWS KMS (Key Management Service) para o DocumentDB e Secrets Manager para gerenciar segredos de banco e chaves de assinatura do JWT.
*   **Contras:**
    *   **Complexidade de Faturamento (Billing):** Requer monitoramento ativo com alertas de orçamento (AWS Budgets) devido ao modelo dinâmico de cobrança.
    *   **Curva de Aprendizado em Redes (VPC):** Configuração fina de segurança (Security Groups, Route Tables, NAT Gateways) exige engenharia especializada.

---

## RFC 002: Escolha do Banco de Dados (Amazon DocumentDB)

### 1. Contexto e Problema
A Ordem de Serviço (OS) de uma oficina mecânica é uma entidade altamente dinâmica e de estrutura hierárquica variável. Ela precisa consolidar em um único registro:
1.  Dados do Cliente (CPF, nome, contato).
2.  Dados do Veículo (Placa, modelo, ano, chassi).
3.  Serviços executados (Mão de obra, mecânico alocado, valores).
4.  Peças substituídas (Quantidade, part-number, preço unitário).
5.  Histórico de Status de Acompanhamento (Diagnóstico, Execução, Finalização) com timestamps para métricas de tempo médio.

Modelos relacionais clássicos exigem múltiplas normalizações (gerando tabelas como `clientes`, `veiculos`, `ordens_servico`, `itens_pecas`, `itens_servicos`, `status_historico`), o que resulta em consultas complexas com múltiplos `JOIN`s, impactando negativamente a latência e aumentando a complexidade do mapeamento na aplicação (impedância objeto-relacional).

### 2. Proposta Técnica (Amazon DocumentDB)
Propõe-se o uso do **Amazon DocumentDB (compatível com MongoDB)**. Por ser um banco NoSQL orientado a documentos, ele permite armazenar a Ordem de Serviço como um documento JSON único, rico e aninhado (embedded document). 

Exemplo conceitual do documento de OS persistido:
```json
 {
        "serviceOrderId": "6a383b7b697771f43a331fba",
        "serviceOrderNumber": "1",
        "customer": {
            "id": "6a383b0f697771f43a331fb5",
            "fullName": "Maria Souza",
            "phoneNumber": "99999-9999",
            "complement": "Apto 42",
            "fullAdress": "Rua das Flores, 123 - Centro, São Paulo - SP, 01310-100"
        },
        "mechanic": null,
        "vehicle": {
            "id": "6a383b1f697771f43a331fb6",
            "plate": "RMA5G42",
            "brand": "Volkswagen",
            "model": "Gol",
            "color": "Branco"
        },
        "labors": {
            "laborsDetails": [
                {
                    "laborId": "6a383b2b697771f43a331fb7",
                    "name": "Troca de óleo",
                    "description": "Troca de óleo do motor com filtro",
                    "laborPrice": 120.00,
                    "startDate": null,
                    "endDate": null,
                    "situation": "APROVADO",
                    "situationDate": "2026-06-21T19:33:01.83"
                }
            ],
            "totalLaborsAmount": 120.00
        },
        "supplys": null,
        "informationText": "Cliente relata barulho ao frear e vibração no volante em alta velocidade.",
        "serviceOrderStatus": "Em execução",
        "statusDate": "21/06/2026 19:33",
        "totalBudgetAmount": "R$ 120,00",
        "createdAt": "21/06/2026 19:28"
    }
```

### 3. Alternativas Consideradas
*   **PostgreSQL (Relacional):** Oferece excelente integridade referencial física por meio de constraints, porém a rigidez do schema exige migrações estruturais complexas a cada modificação nos dados de veículos/peças e gera queries lentas com joins aninhados na geração de relatórios em tempo real.
*   **Amazon DynamoDB (Key-Value/Document):** Escalabilidade extrema, contudo, possui restrições severas de tamanho de item (400KB) e impõe um modelo de modelagem de tabela única (Single Table Design) de alta complexidade que reduz a agilidade no desenvolvimento de consultas ad-hoc para dashboards de tempo médio por status.

### 4. Análise de Prós e Contras (DocumentDB)
*   **Prós:**
    *   **Alta Performance de Leitura:** A OS e todas as suas dependências são recuperadas em uma única operação de busca pelo ID ou código, com latências de milissegundos de dígito único.
    *   **Schema Flexível (Schema-less):** Facilidade em estender atributos de peças ou características específicas de veículos sem a necessidade de paradas de banco ou scripts de migração (DDL).
    *   **Escalabilidade Desacoplada:** O armazenamento escala automaticamente até 64 TiB. As réplicas de leitura podem ser escaladas horizontalmente até 15 instâncias sem impactar a performance de escrita.
*   **Contras:**
    *   **Falta de Constraints Físicas (Foreign Keys):** A integridade relacional entre as coleções de suporte (ex: validar se a peça adicionada à OS existe na coleção de estoque) deve ser assegurada estritamente na camada da aplicação Java usando validações de negócio.
    *   **Custo de Instância Mínima:** Diferente do DynamoDB que oferece camada gratuita robusta sob demanda, o DocumentDB opera baseado em instâncias provisionadas, gerando um custo base inicial fixo maior para ambientes de desenvolvimento/MVP.

### 5. Recomendação
Aprovar a modelagem no **Amazon DocumentDB**. A flexibilidade e a baixa latência nas consultas críticas do fluxo operacional compensam a necessidade de validações robustas adicionais na camada de aplicação em Java.

---

## RFC 003: Estratégia de Autenticação (JWT, Kong Gateway e AWS Lambda em Node)

### 1. Contexto e Problema
O sistema da oficina necessita proteger suas rotas de negócio contra acessos não autorizados. Os clientes precisam se autenticar informando apenas o seu CPF para acessar de forma segura o histórico e o status de suas respectivas Ordens de Serviço. 

O desafio consiste em projetar uma arquitetura de segurança que:
1.  Não onere o microsserviço principal com processos de criptografia, decodificação e validação repetitiva de sessões.
2.  Use uma arquitetura moderna e escalável de microsserviços com segurança de perímetro.
3.  Adote soluções **Serverless** para autenticação e validação de dados sensíveis na base de dados (DocumentDB), em conformidade com as exigências técnicas da Fase 3 do Tech Challenge.

### 2. Proposta Técnica (Kong API Gateway + JWT + AWS Lambda Node)
A solução proposta distribui as responsabilidades de segurança em camadas dedicadas e de alto desempenho:

```
[Cliente] 
    │ (A) Request Login (CPF)
    ▼
[Kong API Gateway] ────(B) Encaminha Login────► [AWS Lambda (Node)]
    ▲                                                │
    │ (D) JWT Emitido                                │ (C) Valida CPF no DocumentDB
    │                                                ▼
[Cliente]                                   [Amazon DocumentDB]
    │ 
    │ (E) Request Protegida (Header: Authorization Bearer <JWT>)
    ▼
[EKS Application Pods (Microsserviço de OS)]
    │ 
    │ 
    ▼
[Backend] (F) Valida JWT Localmente (Spring Security)
    (G) Request Validada e Encaminhada
    

```

#### Camada 1: Gateway de Perímetro (Kong API Gateway)
Atua como o ponto de entrada único para o tráfego externo. O Kong gerencia:
*   **Roteamento:** Mapeia caminhos de URL para os serviços internos no Kubernetes (EKS) ou para funções externas (AWS Lambda).
*   **Segurança Perimetral:** Utiliza o **Basic Auth** para decodificar e validar usuário e senha de forma extremamente rápida.

#### Camada 2: Function Serverless (AWS Lambda em Java)
A lógica de autenticação opera em uma função Lambda Serverless, implementando os seguintes passos:
1.  **Entrada:** Recebe uma requisição POST contendo o CPF do cliente.
2.  **Validação de Negócio:**
    *   Valida se o formato do CPF é válido estruturalmente.
    *   Consulta a coleção de clientes no **Amazon DocumentDB** para verificar se o cliente possui cadastro ativo.
3.  **Geração do Token:** Caso o cliente exista e esteja ativo, o Lambda gera um token **JWT (JSON Web Token)** assinado digitalmente com uma chave privada assimétrica (armazenada de forma segura no GitHub Secrets).
4.  **Retorno:** Devolve o JWT assinado ao Kong, que o entrega de volta ao cliente.

### 3. Alternativas Consideradas
*   **AWS API Gateway em substituição ao Kong:** Embora o AWS API Gateway seja excelente na integração nativa com o Lambda, o uso do Kong se justifica pelo requisito de unificar o gerenciamento e garantir portabilidade híbrida (caso se queira migrar o Kubernetes de nuvem futuramente, a configuração do Kong ingress controller é portada intacta).

---

# ADRs (Architecture Decision Records)

## ADR 001: Padrão de Comunicação (REST APIs via API Gateway)

### Status
Aprovado

### Contexto
O ecossistema do sistema de oficina mecânica será segregado em componentes distintos (Aplicação Principal no Kubernetes para regras de OS, Veículos e Clientes; e Function Serverless para Autenticação). Precisamos estabelecer o padrão arquitetural de comunicação entre esses sistemas e os clientes externos (aplicações web, totens da oficina e aplicativos mobile). 

É necessário garantir uma integração que seja de fácil consumo pelos desenvolvedores front-end, altamente compatível com ferramentas de documentação padrão de mercado (Swagger/OpenAPI) e que tire proveito da segurança e facilidades do Kong API Gateway.

### Decisão
Decidimos utilizar o padrão de comunicação **síncrono baseado em REST APIs sobre protocolo HTTP/S**, gerenciado centralmente por um API Gateway (**Kong**). 

Todos os microsserviços expostos para o ambiente externo devem obrigatoriamente:
1.  Utilizar os métodos HTTP semânticos corretos (`GET` para consultas, `POST` para criação de OS, `PUT` para atualização de dados do veículo, `PATCH` para alteração de status da OS e `DELETE` para exclusões lógicas).
2.  Retornar payloads formatados exclusivamente em **JSON**.
3.  Seguir códigos de status HTTP padronizados (ex: `201 Created` ao criar OS, `200 OK` para atualizações bem-sucedidas, `400 Bad Request` para erros de validação e `401 Unauthorized` para tokens inválidos).
4.  Ter suas assinaturas mapeadas no Swagger, permitindo que o API Gateway faça o roteamento limpo com base nos caminhos (ex: `/api/v1/auth/*` para o Lambda de autenticação e `/api/v1/ordens-servico/*` para a aplicação no EKS).

### Consequências
*   **Positivas:**
    *   **Simplicidade e Adoção:** O modelo REST é amplamente difundido, facilitando o desenvolvimento das integrações por novos membros da equipe.
    *   **Desempenho no Gateway:** O Kong foi otimizado nativamente para processamento de rotas HTTP com latência extremamente baixa.
    *   **Controle Centralizado de Tráfego:** Centralização de Rate Limiting (limitação de taxa por cliente para evitar sobrecarga) e CORS diretamente na camada de rede externa.
*   **Negativas:**
    *   **Comunicação Síncrona:** Chamadas encadeadas de forma síncrona geram acoplamento temporal. Se o banco DocumentDB apresentar instabilidade momentânea durante um fluxo de validação síncrono, a requisição inteira falhará diretamente na tela do usuário final. No entanto, para o escopo operacional de uma oficina, o comportamento síncrono imediato de criação/atualização de OS é desejável para confirmação dos dados na tela de recepção.

---

## ADR 002: Escalabilidade Automática com HPA no Amazon EKS

### Status
Aprovado

### Data
31 de Agosto de 2026

### Contexto
O fluxo operacional de uma oficina mecânica de grande escala apresenta oscilações previsíveis e bruscas de carga. Os maiores volumes de acesso ocorrem no início do dia útil (abertura de OS, check-in dos veículos para diagnóstico) e no final da tarde (conclusão das OS, faturamento e entrega). Manter instâncias ou pods fixos sob dimensionamento máximo gera desperdício severo de recursos financeiros e infraestrutura na nuvem AWS. Por outro lado, o subdimensionamento causará lentidão generalizada nas telas operacionais dos mecânicos e atendentes, podendo parar os pátios de manutenção.

Dada a escolha de rodar a aplicação principal sobre o **Amazon EKS (Kubernetes)**, é necessário implementar uma estratégia nativa de escalabilidade horizontal automática que reaja proativamente à utilização de hardware dos pods para sustentar a demanda de negócios sem intervenção manual.

### Decisão
Decidimos implementar o **Horizontal Pod Autoscaler (HPA)** no cluster **Amazon EKS** para gerenciar dinamicamente a quantidade de réplicas de pods do microsserviço da aplicação principal (Java).

A política de escalabilidade será configurada da seguinte forma através do manifesto Kubernetes e provisionada via Terraform:
1.  **Monitor de Métricas:** Utilização de métricas de **Uso de CPU** e **Consumo de Memória**, obtidas nativamente via componente `Metrics Server` do cluster EKS.
2.  **Limiares de Alvo (Target Thresholds):**
    *   **CPU:** Escalar horizontalmente sempre que a média de utilização de CPU de todos os pods do microsserviço principal ultrapassar **75%** dos recursos solicitados (`limits/requests`).
    *   **Memória:** Escalar horizontalmente se o consumo de memória ultrapassar **80%** de forma constante.
3.  **Configuração de Limites do HPA:**
    *   **Quantidade Mínima de Pods (Min Replicas):** 2 pods (garantindo que mesmo em carga ociosa ou durante atualizações contínuas do cluster, a aplicação mantenha alta disponibilidade com distribuição geográfica em diferentes nós e AZs).
    *   **Quantidade Máxima de Pods (Max Replicas):** 10 pods (estabelecendo um limite de custo de infraestrutura seguro para evitar gastos inesperados com loopings em desenvolvimento ou picos anormais de tráfego).
4.  **Políticas de Arrefecimento (Scale-Down Cooldown):**
    *   Definir um intervalo de arrefecimento de **300 segundos (5 minutos)**. Isso impede que o cluster remova pods apressadamente caso a carga caia por alguns segundos, evitando o comportamento de oscilação rápida ("thrashing") que degrada o desempenho global do sistema.

### Consequências
*   **Positivas:**
    *   **Eficiência de Custo Inteligente:** A infraestrutura encolhe automaticamente fora do horário comercial das oficinas (noites, madrugadas e domingos), reduzindo drasticamente a fatura da AWS.
    *   **Resiliência Sob Sobrecarga:** Caso ocorra um pico inesperado, novas réplicas da aplicação em Java são levantadas em segundos no cluster Kubernetes para dividir a carga operacional, mantendo a experiência do usuário fluida.
    *   **Alta Disponibilidade Garantida:** A manutenção de pelo menos 2 réplicas garante redundância ativa e atualizações *Rolling Updates* sem interrupção de serviço.
*   **Negativas:**
    *   **Gargalos de Inicialização da VM Java (Cold Start do Pod):** Os pods Java sob Spring Boot podem levar alguns segundos adicionais para se inicializar e começar a aceitar conexões (Readiness Probe). Para minimizar essa latência, a equipe deve configurar corretamente as probes de inicialização (`startupProbe`) e otimizar as configurações de heap da JVM nos arquivos de implantação da aplicação.
