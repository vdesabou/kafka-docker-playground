// https://github.com/pedroetb/node-oauth2-server-example
var express = require('express'),
	bodyParser = require('body-parser'),
	OAuth2Server = require('oauth2-server'),
	Request = OAuth2Server.Request,
	Response = OAuth2Server.Response;

var app = express();

app.use(bodyParser.urlencoded({ extended: true }));

app.use(bodyParser.json());

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
var errorCode = 200;

app.post('/', authenticateRequest, (req, res) => {
  res.status(errorCode).json({ message: `Returned status: ${errorCode}` });
  console.log(`[${new Date().toISOString()}] ${req.body}: sending back ${errorCode}`);
});

app.put('/', (req, res) => {
  if(req.body.errorCode && typeof req.body.errorCode === "number"){
    errorCode = req.body.errorCode;
    res.status(200).json({ message: `Error code is now: ${errorCode}` });
  } else {
    res.status(400).json({ message: 'Please provide errorCode in body as number'});
  }
});


///

app.listen(9006);

function obtainToken(req, res) {

	var request = new Request(req);
	var response = new Response(res);

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
