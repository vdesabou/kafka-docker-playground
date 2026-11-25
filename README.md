# 🐳 kafka-docker-playground

**Reproduce any Kafka issue in minutes.** Ready-to-run Apache Kafka® and Confluent examples (170+ connectors, 110+ fully managed, 15+ secured environments, CFK), at any version, and a CLI that tells you what is wrong.

📚 **Documentation: [kafka-docker-playground.io](https://kafka-docker-playground.io/)**

## 🍿 See it in action

<a href="https://kafka-docker-playground.io/#/introduction"><img src="https://kafka-docker-playground.io/videos/find-example.gif" alt="playground find-example" width="49%"></a>
<a href="https://kafka-docker-playground.io/#/introduction"><img src="https://kafka-docker-playground.io/videos/diagnose.gif" alt="playground connector diagnose" width="49%"></a>

More clips on the [website](https://kafka-docker-playground.io/#/introduction), and 2–3 minute narrated walkthroughs, from the symptom to the HTML report, in the [🎬 Bite size sessions](https://kafka-docker-playground.io/#/sessions).

## 🏁 Getting started

```bash
# 1. install the playground (macOS, Linux, WSL)
curl -fsSL https://kafka-docker-playground.io/install.sh | bash

# 2. find the example closest to your case
playground find-example "s3 sink"

# 3. run it, with the Confluent Platform version you need
playground run -f connect/connect-aws-s3-sink/s3-sink.sh --tag 8.4.1
```

Nothing installed yet? Try it in your browser, Docker and the CLI are already set up:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/vdesabou/kafka-docker-playground?quickstart=1)

## ✨ What you can do

- ▶️ **Run** 177 self-managed and 112 fully managed [connector examples](https://kafka-docker-playground.io/#/examples), in 19 secured [environments](https://kafka-docker-playground.io/#/content?id=🔐-environments) or on Kubernetes (`--environment cfk`), with any Confluent Platform or connector version
- 🩺 **Diagnose** with about 300 commands that each answer a support question in one call ([which command do I need?](https://kafka-docker-playground.io/#/which-command)), and shareable [reports](https://kafka-docker-playground.io/#/reports) for logs, dumps, flight recordings and network captures
- 👷 **Reproduce** a customer issue as a [reproduction model](https://kafka-docker-playground.io/#/toolkit-reproduction-models), starting from their config, and find the version where a behaviour changed
- 🎓 **Learn** with [bite size sessions](https://kafka-docker-playground.io/#/sessions), [deep dives](https://kafka-docker-playground.io/#/deep-dives), the [academy](https://kafka-docker-playground.io/#/academy), and [Claude Code](https://kafka-docker-playground.io/#/claude-code)

The full list is on the [website](https://kafka-docker-playground.io/#/introduction?id=✨-what-you-can-do).

## 📊 See what it finds

Real reports, generated from the samples shipped in the repository: browse them all in the [reports](https://kafka-docker-playground.io/#/reports) gallery.

<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/thread-dump.png" alt="thread dump report" width="32%"></a>
<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/benchmark.png" alt="connector benchmark report" width="32%"></a>
<a href="https://kafka-docker-playground.io/#/reports"><img src="https://kafka-docker-playground.io/images/reports/oracle-xstream-report.png" alt="Oracle XStream report" width="32%"></a>

## 💡 Philosophy

Most examples are deliberately minimal: they let you test components quickly, automatically and with any [version](https://kafka-docker-playground.io/#/how-to-use?id=🪄-specify-versions), and above all [build](https://kafka-docker-playground.io/#/toolkit-reproduction-models) your own reproduction models.

## 🙏 Support my work

Love it? Give it a ⭐️ by clicking below:

<a href="https://github.com/vdesabou/kafka-docker-playground/stargazers"><img src="https://img.shields.io/github/stars/vdesabou/kafka-docker-playground?style=social" style="margin-left:0;box-shadow:none;border-radius:0;height:24px"></a>

## ⭐️ Star History

[![Star History Chart](https://star-history.dera.page/svg?repos=vdesabou/kafka-docker-playground&type=date&legend=top-left)](https://star-history.dera.page/#vdesabou/kafka-docker-playground&type=date&legend=top-left)
