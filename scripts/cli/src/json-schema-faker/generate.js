const jsf = require('json-schema-faker');
const fs = require('fs');
const iterations = JSON.parse(process.env.NB_MESSAGES);

const schema = JSON.parse(fs.readFileSync('/tmp/value_schema', 'utf8'));

for (let i = 0; i < iterations; i++) {
  const data = jsf.generate(schema);
  console.log(data);
}
