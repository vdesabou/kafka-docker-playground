const jsf = require('json-schema-faker');
const jsonminify = require('jsonminify');
const fs = require('fs');
const iterations = JSON.parse(process.env.NB_MESSAGES);

const schema = JSON.parse(fs.readFileSync('/tmp/value_schema', 'utf8'));

for (let i = 0; i < iterations; i++) {
  const data = jsf.generate(schema);
  const minifiedData = jsonminify(JSON.stringify(data));
  console.log(minifiedData);
}
