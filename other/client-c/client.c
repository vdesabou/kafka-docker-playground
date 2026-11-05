/*
 * Confluent C/C++ client (librdkafka): producer and consumer of string records.
 *
 * usage: client produce|consume <topic> <config file> [<number of messages, default 10>]
 *
 * The config file holds librdkafka properties, one key=value per line (# comments):
 * see https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md
 *
 * produce: keys key-<i>, values {"count":<i>}, acks=all, one line per delivery report,
 *          exits 1 if a record was not delivered.
 * consume: group <topic>-group from the earliest offset, synchronous commit after each record,
 *          exits 0 once <number of messages> records are consumed, 1 after 60 seconds.
 */
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <librdkafka/rdkafka.h>

#define CONSUME_TIMEOUT_SECONDS 60

static int nb_delivered = 0;
static int nb_failed = 0;

static void usage(void) {
    fprintf(stderr, "usage: client produce|consume <topic> <config file> [<number of messages, default 10>]\n");
    exit(1);
}

static char *trim(char *s) {
    while (isspace((unsigned char)*s))
        s++;
    char *end = s + strlen(s);
    while (end > s && isspace((unsigned char)end[-1]))
        *--end = '\0';
    return s;
}

static void set_or_die(rd_kafka_conf_t *conf, const char *key, const char *value) {
    char errstr[512];
    if (rd_kafka_conf_set(conf, key, value, errstr, sizeof(errstr)) != RD_KAFKA_CONF_OK) {
        fprintf(stderr, "Invalid property %s: %s\n", key, errstr);
        exit(1);
    }
}

/* librdkafka properties of the config file: rd_kafka_conf_set rejects unknown keys */
static rd_kafka_conf_t *load_config(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        perror(path);
        exit(1);
    }
    rd_kafka_conf_t *conf = rd_kafka_conf_new();
    char line[4096];
    int line_number = 0;
    while (fgets(line, sizeof(line), f)) {
        line_number++;
        char *s = trim(line);
        if (*s == '\0' || *s == '#')
            continue;
        char *eq = strchr(s, '=');
        if (!eq) {
            fprintf(stderr, "%s:%d: expected key=value, got: %s\n", path, line_number, s);
            exit(1);
        }
        *eq = '\0';
        set_or_die(conf, trim(s), trim(eq + 1));
    }
    fclose(f);
    return conf;
}

static void delivery_report(rd_kafka_t *rk, const rd_kafka_message_t *m, void *opaque) {
    (void)rk;
    (void)opaque;
    if (m->err) {
        fprintf(stderr, "Failed to deliver record: %s\n", rd_kafka_err2str(m->err));
        nb_failed++;
        return;
    }
    printf("Produced record to %s [%d] at offset %lld\n", rd_kafka_topic_name(m->rkt), (int)m->partition,
           (long long)m->offset);
    nb_delivered++;
}

static int produce(const char *topic, rd_kafka_conf_t *conf, int nb_messages) {
    char errstr[512];
    set_or_die(conf, "acks", "all");
    rd_kafka_conf_set_dr_msg_cb(conf, delivery_report);
    rd_kafka_t *rk = rd_kafka_new(RD_KAFKA_PRODUCER, conf, errstr, sizeof(errstr));
    if (!rk) {
        fprintf(stderr, "Failed to create the producer: %s\n", errstr);
        return 1;
    }

    for (int i = 0; i < nb_messages; i++) {
        char key[32], value[64];
        snprintf(key, sizeof(key), "key-%d", i);
        snprintf(value, sizeof(value), "{\"count\":%d}", i);
        rd_kafka_resp_err_t err;
        /* the local queue is full: serve the delivery reports, then retry */
        while ((err = rd_kafka_producev(rk, RD_KAFKA_V_TOPIC(topic), RD_KAFKA_V_KEY(key, strlen(key)),
                                        RD_KAFKA_V_VALUE(value, strlen(value)),
                                        RD_KAFKA_V_MSGFLAGS(RD_KAFKA_MSG_F_COPY), RD_KAFKA_V_END)) ==
               RD_KAFKA_RESP_ERR__QUEUE_FULL)
            rd_kafka_poll(rk, 100);
        if (err) {
            fprintf(stderr, "Failed to produce record %d: %s\n", i, rd_kafka_err2str(err));
            rd_kafka_destroy(rk);
            return 1;
        }
        rd_kafka_poll(rk, 0);
    }

    if (rd_kafka_flush(rk, 30 * 1000) != RD_KAFKA_RESP_ERR_NO_ERROR)
        fprintf(stderr, "%d records still in the queue after 30 seconds\n", rd_kafka_outq_len(rk));
    rd_kafka_destroy(rk);

    printf("%d records were produced to topic %s\n", nb_delivered, topic);
    return (nb_failed > 0 || nb_delivered != nb_messages) ? 1 : 0;
}

static int consume(const char *topic, rd_kafka_conf_t *conf, int nb_messages) {
    char errstr[512];
    char group[512];
    snprintf(group, sizeof(group), "%s-group", topic);
    set_or_die(conf, "group.id", group);
    set_or_die(conf, "auto.offset.reset", "earliest");
    set_or_die(conf, "enable.auto.commit", "false");

    rd_kafka_t *rk = rd_kafka_new(RD_KAFKA_CONSUMER, conf, errstr, sizeof(errstr));
    if (!rk) {
        fprintf(stderr, "Failed to create the consumer: %s\n", errstr);
        return 1;
    }
    rd_kafka_poll_set_consumer(rk);

    rd_kafka_topic_partition_list_t *topics = rd_kafka_topic_partition_list_new(1);
    rd_kafka_topic_partition_list_add(topics, topic, RD_KAFKA_PARTITION_UA);
    rd_kafka_resp_err_t err = rd_kafka_subscribe(rk, topics);
    rd_kafka_topic_partition_list_destroy(topics);
    if (err) {
        fprintf(stderr, "Failed to subscribe to %s: %s\n", topic, rd_kafka_err2str(err));
        rd_kafka_destroy(rk);
        return 1;
    }

    int nb_consumed = 0;
    time_t start = time(NULL);
    while (nb_consumed < nb_messages) {
        if (time(NULL) - start > CONSUME_TIMEOUT_SECONDS) {
            fprintf(stderr, "Timeout: consumed %d records out of %d after %d seconds\n", nb_consumed, nb_messages,
                    CONSUME_TIMEOUT_SECONDS);
            break;
        }
        rd_kafka_message_t *m = rd_kafka_consumer_poll(rk, 500);
        if (!m)
            continue;
        if (m->err) {
            if (m->err != RD_KAFKA_RESP_ERR__PARTITION_EOF)
                fprintf(stderr, "Consumer error: %s\n", rd_kafka_message_errstr(m));
            rd_kafka_message_destroy(m);
            continue;
        }
        printf("Consumed record from %s [%d] at offset %lld: key=%.*s value=%.*s\n", rd_kafka_topic_name(m->rkt),
               (int)m->partition, (long long)m->offset, (int)m->key_len, m->key ? (const char *)m->key : "",
               (int)m->len, m->payload ? (const char *)m->payload : "");
        err = rd_kafka_commit_message(rk, m, 0 /* synchronous */);
        if (err)
            fprintf(stderr, "Failed to commit offset %lld: %s\n", (long long)m->offset, rd_kafka_err2str(err));
        rd_kafka_message_destroy(m);
        nb_consumed++;
    }

    /* leave the group now, rather than when its session times out */
    rd_kafka_consumer_close(rk);
    rd_kafka_destroy(rk);

    if (nb_consumed < nb_messages)
        return 1;
    printf("%d records were consumed from topic %s by group %s\n", nb_consumed, topic, group);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4 || argc > 5)
        usage();
    const char *mode = argv[1];
    const char *topic = argv[2];
    int nb_messages = argc == 5 ? atoi(argv[4]) : 10;
    if (nb_messages <= 0)
        usage();

    printf("librdkafka %s\n", rd_kafka_version_str());
    rd_kafka_conf_t *conf = load_config(argv[3]);

    if (strcmp(mode, "produce") == 0)
        return produce(topic, conf, nb_messages);
    if (strcmp(mode, "consume") == 0)
        return consume(topic, conf, nb_messages);
    usage();
    return 1;
}
