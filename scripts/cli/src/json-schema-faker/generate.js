const jsf = require('json-schema-faker');
const jsonminify = require('jsonminify');
const fs = require('fs');
const iterations = JSON.parse(process.env.NB_MESSAGES);
const schema_name = process.env.SCHEMA;
const schema = JSON.parse(fs.readFileSync(schema_name, 'utf8'));

for (let i = 0; i < iterations; i++) {
  const data = jsf.generate(schema);
  const minifiedData = jsonminify(JSON.stringify(data));
  console.log(minifiedData);
}
// https://github.com/json-schema-faker/json-schema-faker/tree/master/docs