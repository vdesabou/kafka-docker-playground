const express = require('express');
const app = express();

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

let errorCode = 200;
let delay = 0; // response delay in ms
let responseBody = {}; // response body
let closeConnection = false; // flag to track connection closure

// Sample data for Elasticsearch search_after pagination
const INITIAL_TIMESTAMP = 1647948000000;
const PAGE_SIZE = 3; // Number of documents per page (matching the example: 3 docs)
const TOTAL_DOCUMENTS = 15; // Total number of documents to simulate
const MAX_TIMESTAMP = INITIAL_TIMESTAMP + (TOTAL_DOCUMENTS * 1000); // Last timestamp

const generateElasticsearchDocuments = (afterTime, pageSize) => {
  const hits = [];
  const startTime = afterTime || INITIAL_TIMESTAMP; // Initial timestamp if not provided
  
  for (let i = 0; i < pageSize; i++) {
    const timestamp = startTime + (i * 1000) + 1000; // Increment by 1 second for each doc
    
    // Stop generating documents if we've reached the maximum
    if (timestamp > MAX_TIMESTAMP) {
      break;
    }
    
    hits.push({
      "_index": "test-index",
      "_id": `doc_${timestamp}`,
      "_score": null,
      "_source": {
        "name": `Name${timestamp}`,
        "time": timestamp.toString()
      },
      "sort": [timestamp] // The sort value used for search_after
    });
  }
  return hits;
};

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

// Elasticsearch Search API with search_after pagination endpoint
app.post('/test-index/_search', (req, res) => {
  console.log(`[${new Date().toISOString()}] POST /test-index/_search`);
  console.log('Request body:', JSON.stringify(req.body, null, 2));
  
  // Extract search_after value from request body
  const searchAfter = req.body.search_after ? req.body.search_after[0] : null;
  const size = req.body.size || 100;
  const sort = req.body.sort || [{"@time": "asc"}];
  
  console.log(`search_after: ${searchAfter}, size: ${size}`);
  
  // Generate documents starting from search_after timestamp
  const hits = generateElasticsearchDocuments(searchAfter, Math.min(size, PAGE_SIZE));
  
  // Build Elasticsearch response format matching the exact structure
  const response = {
    "took": Math.floor(Math.random() * 500) + 100, // Random value between 100-600ms
    "timed_out": false,
    "_shards": {
      "total": 1,
      "successful": 1,
      "skipped": 0,
      "failed": 0
    },
    "hits": {
      "total": {
        "value": hits.length,
        "relation": "eq"
      },
      "max_score": null,
      "hits": hits
    }
  };
  
  // Get the last sort value for the next search_after
  const lastSortValue = hits.length > 0 ? hits[hits.length - 1].sort[0] : null;
  console.log(`Returning ${hits.length} documents, last sort value: ${lastSortValue}`);
  
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
