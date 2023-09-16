const express = require('express');
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} to ${req.url}`);
  next();
});

// https://stackoverflow.com/questions/9177049/express-js-req-body-undefined
var errorCode = 200;

app.get('/', (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
  console.log(req.body); // the posted data
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.post('/', (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
  console.log(req.body); // the posted data
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`);
});

app.put('/', (req, res) => {
  if(req.body.errorCode && typeof req.body.errorCode === "number"){
    errorCode = req.body.errorCode;
    res.status(200).json({ message: `Error code is now: ${errorCode}` });
  } else {
    res.status(400).json({ message: 'Please provide errorCode in body as number'});
  }
});

app.listen(9006, () => console.log('Server running...'));
