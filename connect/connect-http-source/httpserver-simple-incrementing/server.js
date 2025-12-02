const express = require('express');
const app = express();

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

let errorCode = 200;
let delay = 0; // response delay in ms
let responseBody = {}; // response body
let closeConnection = false; // flag to track connection closure


app.use((req, res, next) => {
  setTimeout(() => {
    next();
  }, delay);
});

app.use((req, res, next) => {
  if (closeConnection) {
    console.log(`[${new Date().toISOString()}] Closing connection for ${req.method} to ${req.url}`);
    req.socket.destroy(); // Close the connection without sending a response
  } else {
    next();
  }
});

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} to ${req.url}`);
  console.log(`Request size: ${req.get('Content-Length')} bytes`);
  next();
});

app.get('/', (req, res) => {
  res.status(errorCode)
    .set('Content-Type', 'application/json')
    .set('Custom-Header', 'Hello')
    .json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.post('/', (req, res) => {
  res.status(errorCode)
    .set('Content-Type', 'application/json')
    .set('Custom-Header', 'Hello')
    .json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.put('/', (req, res) => {
  res.status(errorCode)
    .set('Content-Type', 'application/json')
    .set('Custom-Header', 'Hello')
    .json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.delete('/', (req, res) => {
  res.status(errorCode)
    .set('Content-Type', 'application/json')
    .set('Custom-Header', 'Hello')
    .json(responseBody);
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

app.put('/set-connection-closed', (req, res) => {
  closeConnection = true;
  console.log(`[${new Date().toISOString()}] Connection closure enabled`);
  res.status(200).json({ message: 'Connection closure enabled' });
});

// -----------------------------------------------------------------------------
// Confluence Cloud style SIMPLE_INCREMENTING pagination
// Endpoint: /wiki/rest/api/space?start=<offset>&limit=<limit>
// - start: index of first item to return (base 0)
// - limit: number of items per page
// Behavior:
//   * Initial dataset seeded.
//   * Every GROWTH_INTERVAL_MS a random number of new spaces is appended.
//   * If a request asks for start beyond current length, returns empty results array.
//   * Connector (SIMPLE_INCREMENTING) should not advance offset on empty response.
// -----------------------------------------------------------------------------

const INITIAL_SPACES = 15;
const SPACE_GROWTH_INTERVAL_MS = 7000; // every 7s add some new spaces
const MIN_NEW_SPACES = 1;
const MAX_NEW_SPACES = 4;
let spaces = [];
let nextSpaceId = 1000;

function makeSpace(idx) {
  const id = nextSpaceId++;
  return {
    id: id,
    key: `~user${id}`,
    name: `Space ${idx} user${id}`,
    type: 'personal',
    status: 'current',
    _expandable: {
      settings: `/rest/api/space/~user${id}/settings`,
      metadata: '',
      operations: '',
      lookAndFeel: `/rest/api/settings/lookandfeel?spaceKey=~user${id}`,
      identifiers: '',
      permissions: '',
      icon: '',
      description: '',
      theme: `/rest/api/space/~user${id}/theme`,
      history: '',
      homepage: `/rest/api/content/${id + 5000}`
    },
    _links: {
      webui: `/spaces/~user${id}`,
      self: `https://example.atlassian.net/wiki/rest/api/space/~user${id}`
    }
  };
}

// Seed initial spaces
for (let i = 0; i < INITIAL_SPACES; i++) {
  spaces.push(makeSpace(i));
}

setInterval(() => {
  const add = Math.floor(Math.random() * (MAX_NEW_SPACES - MIN_NEW_SPACES + 1)) + MIN_NEW_SPACES;
  for (let i = 0; i < add; i++) {
    spaces.push(makeSpace(spaces.length));
  }
  console.log(`[${new Date().toISOString()}] Added ${add} new Confluence spaces. Total now: ${spaces.length}`);
}, SPACE_GROWTH_INTERVAL_MS);

app.get('/wiki/rest/api/space', (req, res) => {
  const start = parseInt(req.query.start || '0', 10);
  const limit = parseInt(req.query.limit || '1', 10);
  const end = start + limit;
  let slice = [];
  if (start < spaces.length) {
    slice = spaces.slice(start, Math.min(end, spaces.length));
  }
  const size = slice.length;
  const baseUrl = 'https://example.atlassian.net/wiki';
  const selfLink = `${baseUrl}/rest/api/space`;
  const nextStart = start + size;
  const hasMore = nextStart < spaces.length;
  const response = {
    results: slice,
    start: start,
    limit: limit,
    size: size,
    _links: {
      base: baseUrl,
      context: '/wiki',
      self: selfLink
    }
  };
  if (hasMore) {
    response._links.next = `/rest/api/space?next=true&limit=${limit}&start=${nextStart}`;
  }
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${JSON.stringify(response)}`); 
  console.log(`[${new Date().toISOString()}] Confluence GET start=${start} limit=${limit} size=${size} total=${spaces.length}`);
  res.status(200).json(response);
});

// Wildcard route to accept any path
app.all('*', (req, res) => {
  res.status(errorCode)
    .set('Content-Type', 'application/json')
    .set('Custom-Header', 'Hello')
    .json(responseBody);
  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${errorCode}`); 
});

app.listen(9006, () => console.log('Server running on port 9006...'));
