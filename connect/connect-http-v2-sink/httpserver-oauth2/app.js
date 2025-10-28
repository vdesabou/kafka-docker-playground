// https://github.com/pedroetb/node-oauth2-server-example
var express = require('express'),
	OAuth2Server = require('oauth2-server'),
	Request = OAuth2Server.Request,
	Response = OAuth2Server.Response;

var app = express();

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} to ${req.url}`);
  console.log(`Request size: ${req.get('Content-Length')} bytes`);
  next();
});

app.oauth = new OAuth2Server({
	model: require('./model.js'),
	accessTokenLifetime: 60 * 60, // one hour valid
	allowBearerTokensInQueryString: true
});

app.all('/oauth/token', obtainToken);

app.get('/', authenticateRequest, function(req, res) {

	res.send('Congratulations, you are in a secret area!');
});

///
// https://stackoverflow.com/questions/9177049/express-js-req-body-undefined
let errorCode = 200;
let delay = 0; // response delay in ms
let responseBody = {}; // response body

app.use((req, res, next) => {
  setTimeout(() => {
    next();
  }, delay);
});

app.post('/', authenticateRequest, (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.put('/', authenticateRequest, (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.delete('/', authenticateRequest, (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
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


///

app.listen(9006);

function obtainToken(req, res) {

	var request = new Request(req);
	var response = new Response(res);

	console.log("headers:");
	console.log(req.headers);
	console.log("body:");
	console.log(req.body);

	return app.oauth.token(request, response)
		.then(function(token) {

			res.json(token);
		}).catch(function(err) {

			res.status(err.code || 500).json(err);
		});
}

function authenticateRequest(req, res, next) {

	var request = new Request(req);
	var response = new Response(res);

	return app.oauth.authenticate(request, response)
		.then(function(token) {

			next();
		}).catch(function(err) {

			res.status(err.code || 500).json(err);
		});
}
