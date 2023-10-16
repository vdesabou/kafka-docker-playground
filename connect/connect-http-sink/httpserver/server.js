const express = require('express');
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

let errorCode = 200;
let delay = 0; // response delay in ms
let responseBody = {}; // response body

app.use((req, res, next) => {
  setTimeout(() => {
    next();
  }, delay);
});

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} to ${req.url}`);
  next();
});

app.get('/', (req, res) => {
  res.status(errorCode).json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.post('/', (req, res) => {
  res.status(errorCode).json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.put('/', (req, res) => {
  res.status(errorCode).json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.put('/set-response-error-code', (req, res) => {
  if(req.body.errorCode && typeof req.body.errorCode === "number") {
    errorCode = req.body.errorCode;
    res.status(200).json({ message: `Error code is now: ${errorCode}` });
  } else {
    res.status(400).json({ message: 'Please provide errorCode in body as number'});
  }
});

app.put('/set-response-time', (req, res) => {
  if(req.body.delay && typeof req.body.delay === "number") {
    delay = req.body.delay;
    res.status(200).json({ message: `Response delay is now: ${delay} ms` });
  } else {
    res.status(400).json({ message: 'Please provide delay in body as number'});
  }
});

app.put('/set-response-body', (req, res) => {
  if(req.body && typeof req.body === "object") {
    responseBody = req.body;
    res.status(200).json({ message: 'Response body set successfully'});
  } else {
    res.status(400).json({ message: 'Please provide response body as JSON'});
  }
});

app.listen(9006, () => console.log('Server running...'));
