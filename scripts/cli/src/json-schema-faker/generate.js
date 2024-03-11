const jsf = require('json-schema-faker');
jsf.extend('faker', () => require('@faker-js/faker'));
const jsonminify = require('jsonminify');
const fs = require('fs');

if(process.env.NO_NULL == "true") {
  jsf.option('omitNulls', 'true');
}
const iterations = JSON.parse(process.env.NB_MESSAGES);

const refs_name = process.env.REFS;
let refs;
if (refs_name) {
  refs = JSON.parse(fs.readFileSync(refs_name, 'utf8'));
}

const schema_name = process.env.SCHEMA;
const schema = JSON.parse(fs.readFileSync(schema_name, 'utf8'));

for (let i = 0; i < iterations; i++) {
  let data;
  if (refs_name) {
    data = jsf.generate(schema, refs);
  } else {
    data = jsf.generate(schema);
  }
  const minifiedData = jsonminify(JSON.stringify(data));
  console.log(minifiedData);
}
// https://github.com/json-schema-faker/json-schema-faker/tree/master/docs

// https://github.com/json-schema-faker/json-schema-faker/blob/master/docs/USAGE.md