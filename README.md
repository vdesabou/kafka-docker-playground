<div align="center">

# 🐳 kafka-docker-playground

### Reproduce any Kafka issue in minutes

Ready-to-run Apache Kafka® and Confluent examples, at any version, and a CLI that tells you what is wrong.

<a href="https://kafka-docker-playground.io/#/how-to-use?id=%e2%9a%a1-install-in-one-command"><img src="https://img.shields.io/badge/⚡_Install_in_one_command-d7eff6?style=for-the-badge" alt="Install in one command"></a>
<a href="https://kafka-docker-playground.io/#/examples"><img src="https://img.shields.io/badge/👾_Find_an_example-2b3a42?style=for-the-badge" alt="Find an example"></a>
<a href="https://kafka-docker-playground.io/#/which-command"><img src="https://img.shields.io/badge/🧭_Which_command_do_I_need%3F-2b3a42?style=for-the-badge" alt="Which command do I need?"></a>
<a href="https://codespaces.new/vdesabou/kafka-docker-playground?quickstart=1"><img src="https://img.shields.io/badge/🌐_Try_in_your_browser-2b3a42?style=for-the-badge" alt="Try in your browser"></a>

**170+** self-managed connectors &nbsp;·&nbsp; **110+** fully managed connectors &nbsp;·&nbsp; **90+** other examples (ksqlDB, Flink, clients, multi-data-center…) &nbsp;·&nbsp; **15+** secured environments &nbsp;·&nbsp; **300** `playground` CLI commands to troubleshoot

📚 **[kafka-docker-playground.io](https://kafka-docker-playground.io/)**

<a href="https://kafka-docker-playground.io/"><img src="https://kafka-docker-playground.io/videos/find-example.gif" alt="playground find-example" width="49%"></a>
<a href="https://kafka-docker-playground.io/"><img src="https://kafka-docker-playground.io/videos/diagnose.gif" alt="playground connector diagnose" width="49%"></a>

<sub>More clips (logs, analyze, validate, repro, pipeline, Claude Code) on the <a href="https://kafka-docker-playground.io/">website</a>, and 2–3 minute narrated walkthroughs in the <a href="https://kafka-docker-playground.io/#/sessions">🎬 Bite size sessions</a>.</sub>

</div>

## 🏁 Getting started

```bash
# 1. install the playground (macOS, Linux, WSL)
curl -fsSL https://kafka-docker-playground.io/install.sh | bash

# 2. find the example closest to your case
playground find-example "s3 sink"

# 3. run it, with the Confluent Platform version you need
playground run -f connect/connect-aws-s3-sink/s3-sink.sh --tag 8.4.1
```

Prefer menus? `playground run` alone lets you pick the example and its options. Nothing installed yet? [Try it in your browser](https://codespaces.new/vdesabou/kafka-docker-playground?quickstart=1): Docker and the CLI are already set up.

## ✨ What you can do

| You want to | The playground gives you |
| --- | --- |
| ▶️ **Run** | 177 self-managed and 112 fully managed [connector examples](https://kafka-docker-playground.io/#/examples), 19 secured [environments](https://kafka-docker-playground.io/#/content?id=🔐-environments) (SASL, SSL, Kerberos, LDAP, RBAC, OAuth…), Kubernetes with `--environment cfk`, any Confluent Platform or connector version, Docker or Podman |
| 🚑 **Diagnose** | about 300 commands that each answer a support question in one call: [find the right one](https://kafka-docker-playground.io/#/which-command) with `playground find-command`, `connector diagnose`, `show-lag`, `analyze logs` and shareable [reports](https://kafka-docker-playground.io/#/reports) for dumps, flight recordings and network captures |
| 👷 **Reproduce** | turn an example into a [reproduction model](https://kafka-docker-playground.io/#/toolkit-reproduction-models), start from the customer's config as is (CFK, Strimzi, terraform, `.properties`), find the version where a behaviour changed with `repro bisect`, [benchmark](https://kafka-docker-playground.io/#/toolkit-performance?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector) a connector |
| 🎓 **Learn** | [bite size sessions](https://kafka-docker-playground.io/#/sessions), [deep dives](https://kafka-docker-playground.io/#/deep-dives), the [academy](https://kafka-docker-playground.io/#/academy), [how it works](https://kafka-docker-playground.io/#/how-it-works), and [Claude Code](https://kafka-docker-playground.io/#/claude-code) |

The full list is on the [website](https://kafka-docker-playground.io/#/introduction?id=✨-what-you-can-do).

## 📊 See what it finds

Real reports, generated from the samples shipped in the repository: browse them all in the [reports](https://kafka-docker-playground.io/#/reports) gallery.

<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/thread-dump.png" alt="thread dump report" width="32%"></a>
<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/benchmark.png" alt="connector benchmark report" width="32%"></a>
<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/oracle-xstream-report.png" alt="Oracle XStream report" width="32%"></a>

## 💡 Philosophy

Most examples are deliberately minimal: they let you test components quickly, automatically and with any [version](https://kafka-docker-playground.io/#/how-to-use?id=🪄-specify-versions), and above all [build](https://kafka-docker-playground.io/#/toolkit-reproduction-models) your own reproduction models.

## ⭐️ Support my work

Love it? Give it a ⭐️:

<a href="https://github.com/vdesabou/kafka-docker-playground/stargazers"><img src="https://img.shields.io/github/stars/vdesabou/kafka-docker-playground?style=social" alt="GitHub stars"></a>

[![Star History Chart](https://star-history.dera.page/svg?repos=vdesabou/kafka-docker-playground&type=date&legend=top-left)](https://star-history.dera.page/#vdesabou/kafka-docker-playground&type=date&legend=top-left)
