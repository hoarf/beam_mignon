---
title: "eclero, coletando métricas"
description: ""
toc: true
draft: true
date: 2020-01-29T18:43:50+02:00
series: ["observability"] 
tags: ["code", "observable", "metrics"]
featured_image: 'images/featured/observability-1-0.jpg'
---

Nesta série de posts sobre Observability vamos instrumentar e estruturar uma aplicação com o objetivo de estudar as estratégias escolhidas.

## O que é Observability

Resumidamente é coletar várias visões internas e externas de uma aplicação e correlacionar posteriormente em um sistema externo.

O fato é que não é apenas monitoramento de contadores por exemplo `requests por segundo` ou `quantidade de memória`. Mas um conjunto de dados a serem externalizados para posterior análize.

As aplicações e dependências precisam ser instrumentados para enviarem diferentes visões:

* métricas
* traces
* logs
* alertas

## Observability para BEAM

Existem várias bibliotecas e iniciativas quando usamos Elixir/Erlang. E também existe a dúvida de qual utilizar. De fato um dos WG (Working Groups) chamado [Observability Working Group](https://erlef.org/wg/observability) da ERLF (Erlang Ecosystem Foundation) é para ajudar a organizar as iniciativas.

Há uma lista de bibliotecas relacionadas a observability aqui: https://github.com/erlef/eef-observability-wg

Neste post vamos utilizar o projeto `beam-telemetry`.

## beam-telemetry

`beam-telemetry` é um projeto no qual possui algumas bibliotecas para organizar e estruturar o envio de métricas.

A principal biblioteca é `telemetry` no qual quando a aplicação precisa emitir uma métrica, a função `telemetry:execute/3` é chamada para realizar a operação.

Instrumentar uma aplicação para o envio de métricas deve ser uma tarefa de dois passos:

1. Definir as métricas que são importantes
2. Chamar a função telemetry:execute/3 nos pontos estratágicos

O propósito da biblioteca telemetry é implementar uma interface única para todas as aplicações que precisam enviar métricas.

Uma vez definida a interface, é necessário definir quais os tipos de métricas queremos enviar. A biblioteca `telemetry_metrics` implementa estas definições nas quais podem ser:

* counter: número total da métrica
* last_value: último valor da métrica
* sum: matem a somatória da métrica
* summary: calcula estatísticas da métrica
* distribution: constroi um histograma de acordo coms os buckets configurados

Antes de enviar a métrica para algum outro sistema externo, a decisão do que fazer e como estruturar cada métrica é responsabilidade de um tipo de aplicação chamada _reporter_. beam-telemetry traz alguns reporters oficiais:

* [prometheus](https://github.com/beam-telemetry/telemetry_metrics_prometheus)
* [statsd](https://github.com/beam-telemetry/telemetry_metrics_statsd)

E outros criados pela comunidade

* [zabbix](https://github.com/lukaszsamson/telemetry_metrics_zabbix)
* [riemann](https://github.com/joaohf/telemetry_metrics_riemann)

Mas qual é a função de um reporter? Preparar e enviar a métrica para outro sistema. Por exemplo, o reporter para prometheus [TelemetryMetricsPrometheus.Core](https://github.com/beam-telemetry/telemetry_metrics_prometheus_core/tree/master/lib/core) precisa preparar os _scrapes_ para que o Prometheus colete adequadamente. Então este reporter precisa fazer agregações na aplicação para cada nova métrica emitida pelo telemetry.

Por outro lado, os reporters [TelemetryMetricsStatsd](https://github.com/beam-telemetry/telemetry_metrics_statsd), [TelemetryMetricsRiemann](https://github.com/joaohf/telemetry_metrics_riemann) apenas preparam e enviam a métrica no formato esperado pelos sistemas externos. Nenhuma operação de agregação é realizada na aplicação.

Para implementar algum outro reporter o projeto beam-telemetry definiou algumas guias gerais de como fazer aqui: 
https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#module-reporters

## Definindo as métricas

Usando a API da biblioteca [Telemetry.Metrics](https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html) definimos as métricas no seguinte formato:

{{< highlight erlang >}}
Telemetry.Metrics.counter("http.request.stop.duration")
{{< / highlight >}}

Onde:

* `Telemetry.Metrics.counter` é o tipo da métrica
* `"http.request.stop.duration"` é interpretado da seguinte forma:
 * `"http.request.stop"`: nome do evento (_event name_)
 * `"duration"`: medição (measurement)

A string `"http.request.stop.duration"` pode ser representada como uma lista de atoms também: `[http, request, stop, duration]`.

Cada tipo de métrica pode receber diversos parâmetros. Recomendo usar como referência a documentação https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html#functions

O importante é saber que uma métrica é composto por _event name_ e _measurement_. Então podemos ter vários _measurements_ dentro de um _event name_.

Na sessão {{< ref "#Exemplo: eclero com telemetry" >}} vamos implementar as métricas mas antes precisamos definir o que queremos contar. No momento estou interessado em saber:

* A quantidade de http requests no endpoint _/check_ foram feitas, `[http, request, check, done]`
* A quantidade de nós online no cluster, `[decision, server, nodes, up]`
* A quantidade de nós offline no cluster, `[decision, server, nodes, down]`

## Exemplo: eclero com telemetry

Neste exemplo vamos intrumentar a aplicação eclero utilizando telemetry enviando as métricas para o reporter riemann.

O módulo _eclero\_metric_ foi criado para conter toda a implementação das métricas. A função `eclero_metric:options()` retorna a configuração necessária para o reporter `TelemetryMetricsRiemann` funcionar.

{{< ghcode title="Configuração do telemetry report" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_metric.erl" start=8 end=14 highlight="linenos=inline" >}}

Na função `eclero_metric:metrics()` definimos todas as métricas que serão inicializadas pelo `telemetry`.

{{< ghcode title="Definição das métricas" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_metric.erl" start=17 end=28 highlight="linenos=inline" >}}

Também definimos funções nas quais preenchem os valores correto da API do `telemetry`. Definindo as próprias funções é útil para fazermos manutenção, mudança de API ou algum tipo de transformação nos dados. Uma alternativa é chamar a função `telemetry:execute/3` em vários pontos do código.

{{< ghcode title="Acessores das métricas" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_metric.erl" start=31 end=42 highlight="linenos=inline" >}}

O próximo passo foi selecionar os pontos que queremos coletar métricas:

* A quantidade de http requests no endpoint _/check_ foram feitas:
{{< ghcode title="" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_http.erl" start=36 end=41 highlight="linenos=inline" >}}
* A quantidade de nós online e offline no cluster:
{{< ghcode title="" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_decision_server.erl" start=57 end=67 highlight="linenos=inline" >}}
* A quantidade de nós offline no cluster:
{{< ghcode title="" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_decision_server.erl" start=69 end=79 highlight="linenos=inline" >}}

O último passo foi adicionar o processo do TelemetryReportRiemann na árvore de supervisão da aplicação:

{{< ghcode title="" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="apps/eclero/src/eclero_sup.erl" start=28 end=43 highlight="linenos=inline" >}}

### riemann

Para verificar se as métricas estão sendo enviadas para o servidor, precisamos subir um [servidor riemann local](https://riemann.io/quickstart.html):

````bash
wget https://github.com/riemann/riemann/releases/download/0.3.5/riemann-0.3.5.tar.bz2
tar jxf riemann-0.3.5.tar.bz2 
cd rieamnn-0.3.5
bin/riemann start
````

Com o servidor executando em um shell, vamos inspecionar os pacotes enviados. Pois no momento não estamos intressados em ver as métricas do lado do riemann server.

### Verificando as métricas

Utilizando wireshark, podemos inspecionar os pacotes enviados usando o [protocolo riemann](https://riemann.io/concepts.html).

## Erlang com Elixir, gestão de dependências

eclero utiliza rebar3 para gestão de dependências. Entretando telemetry_metric_riemann foi implementado em Elixir, usando mix como gestão de dependência.

Utilizando um plugin chamado [rebar_mix](https://github.com/Supersonido/rebar_mix) foi possivel utilizar os pacotes Elixir com rebar3.

O interessante desda abordagem é a possibilidade de utilizar várias bibliotecas desenvolvidas em Elixir a partir do Erlang. Afinal, tudo é BEAM.

## Conclusão

Intrumentar uma aplicação é simples e o tempo deve ser gasto na definição das métricas, tentando responder se determinada métrica faz sentido e ajuda na identificação de problemas relacionados as regras de negócio. Todas as métricas que ajudem durante uma análise da saúde da aplicação fazem sentido de serem implementadas.

## Intro 2

{{< figure figcaption="New homepage with blog posts, smaller portfolio and different colour mix" >}}
  {{< placeholder >}}
{{< /figure >}}

{{< figure figcaption="New homepage with blog posts, smaller portfolio and different colour mix" >}}
  {{< placeholder >}}
{{< /figure >}}

{{< note >}}
The key distinction for Hugo versions 0.20 and newer is that Hugo looks at an output format's `Name` and MediaType's `Suffix` when choosing the template used to render a given `Page`.
{{< /note >}}


{{< tip >}}
The key distinction for Hugo versions 0.20 and newer is that Hugo looks at an output format's `Name` and MediaType's `Suffix` when choosing the template used to render a given `Page`.
{{< /tip >}}

{{< warning >}}
The key distinction for Hugo versions 0.20 and newer is that Hugo looks at an output format's `Name` and MediaType's `Suffix` when choosing the template used to render a given `Page`.
{{< /warning >}}

{{< figure figcaption="New homepage with blog posts, smaller portfolio and different colour mix" >}}
  {{< placeholder >}}
{{< /figure >}}

{{< ghcode title="rebar3 configuração" lang="erlang" owner="joaohf" repo="eclero" ref="master" path="rebar.config" highlight="linenos=inline,hl_lines=8 15-17" >}}
