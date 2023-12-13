# FileStream Source connector

## Objective

Quickly test [FileStream Source](https://docs.confluent.io/home/connect/filestream_connector.html#filesource-connector) connector.


## How to run

Simply run:

```
$ playground run -f filestream-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Details of what the script is doing

Creating FileStream source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
               "topic": "filestream",
               "file": "$INPUT_FILE",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-source/config | jq .
```

Verifying topic `filestream`

```bash
playground topic consume --topic filestream --min-expected-messages 10 --timeout 60
```

Results:

```json
"{\"id\":1,\"first_name\":\"Rikki\",\"last_name\":\"Wedgwood\",\"email\":\"rwedgwood0@ebay.com\",\"gender\":\"Polygender\",\"ip_address\":\"247.229.211.141\",\"last_login\":\"2014-06-26T11:29:16Z\",\"account_balance\":18953.38,\"country\":\"BR\",\"favorite_color\":\"#9c2037\"}"
"{\"id\":2,\"first_name\":\"Pen\",\"last_name\":\"Bott\",\"email\":\"pbott1@imageshack.us\",\"gender\":\"Non-binary\",\"ip_address\":\"158.1.71.176\",\"last_login\":\"2014-07-26T18:13:31Z\",\"account_balance\":7214.87,\"country\":\"SE\",\"favorite_color\":\"#019fa9\"}"
"{\"id\":3,\"first_name\":\"Lauren\",\"last_name\":\"Bader\",\"email\":\"lbader2@businessweek.com\",\"gender\":\"Polygender\",\"ip_address\":\"31.165.133.163\",\"last_login\":\"2017-02-20T23:22:18Z\",\"account_balance\":14389.06,\"country\":\"BR\",\"favorite_color\":\"#b7612c\"}"
"{\"id\":4,\"first_name\":\"Monica\",\"last_name\":\"Brindley\",\"email\":\"mbrindley3@oakley.com\",\"gender\":\"Genderqueer\",\"ip_address\":\"141.130.145.160\",\"last_login\":\"2015-12-15T13:56:01Z\",\"account_balance\":19177.88,\"country\":\"SE\",\"favorite_color\":\"#4d17a0\"}"
"{\"id\":5,\"first_name\":\"Feodor\",\"last_name\":\"Blomefield\",\"email\":\"fblomefield4@twitpic.com\",\"gender\":\"Female\",\"ip_address\":\"60.153.61.248\",\"last_login\":\"2016-01-29T13:46:07Z\",\"account_balance\":3737.65,\"country\":\"MX\",\"favorite_color\":\"#1108e5\"}"
"{\"id\":6,\"first_name\":\"Marnie\",\"last_name\":\"Francklin\",\"email\":\"mfrancklin5@phoca.cz\",\"gender\":\"Female\",\"ip_address\":\"158.163.95.180\",\"last_login\":\"2016-11-09T13:38:12Z\",\"account_balance\":8322.94,\"country\":\"AR\",\"favorite_color\":\"#0cdb4e\"}"
"{\"id\":7,\"first_name\":\"Retha\",\"last_name\":\"Drinan\",\"email\":\"rdrinan6@delicious.com\",\"gender\":\"Bigender\",\"ip_address\":\"37.60.246.100\",\"last_login\":\"2018-02-11T16:50:16Z\",\"account_balance\":15798.99,\"country\":\"CO\",\"favorite_color\":\"#5720db\"}"
"{\"id\":8,\"first_name\":\"Tomaso\",\"last_name\":\"Kehoe\",\"email\":\"tkehoe7@nyu.edu\",\"gender\":\"Non-binary\",\"ip_address\":\"235.116.106.72\",\"last_login\":\"2014-12-29T20:56:14Z\",\"account_balance\":7083.89,\"country\":\"PH\",\"favorite_color\":\"#c43252\"}"
"{\"id\":9,\"first_name\":\"Waly\",\"last_name\":\"Munning\",\"email\":\"wmunning8@vkontakte.ru\",\"gender\":\"Genderqueer\",\"ip_address\":\"220.42.8.199\",\"last_login\":\"2018-01-02T19:06:05Z\",\"account_balance\":2236.4,\"country\":\"CO\",\"favorite_color\":\"#a09335\"}"
"{\"id\":10,\"first_name\":\"Orv\",\"last_name\":\"Teeney\",\"email\":\"oteeney9@zimbio.com\",\"gender\":\"Genderfluid\",\"ip_address\":\"163.159.171.153\",\"last_login\":\"2018-07-25T06:01:09Z\",\"account_balance\":7867.97,\"country\":\"ID\",\"favorite_color\":\"#a37fc1\"}"
Processed a total of 10 messages
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
