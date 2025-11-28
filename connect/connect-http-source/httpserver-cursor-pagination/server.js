const express = require('express');
const app = express();

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));

let errorCode = 200;
let delay = 0; // response delay in ms
let responseBody = {}; // response body
let closeConnection = false; // flag to track connection closure

// Sample data for cursor pagination (Google Cloud Storage API style)
const generateSampleObjects = (startIndex, count) => {
  const objects = [];
  for (let i = 0; i < count; i++) {
    const index = startIndex + i;
    objects.push({
      "kind": "storage#object",
      "id": `object_id_${index}`,
      "selfLink": `https://www.googleapis.com/storage/v1/b/test-bucket/o/object_${index}`,
      "mediaLink": `https://storage.googleapis.com/download/storage/v1/b/test-bucket/o/object_${index}`,
      "name": `file_${index}.txt`,
      "bucket": "test-bucket",
      "generation": `166912498201894${index}`,
      "metageneration": "1",
      "contentType": "text/plain",
      "storageClass": "STANDARD",
      "size": `${14552 + index}`,
      "md5Hash": `md5_hash_${index}`,
      "crc32c": `crc32c_${index}`,
      "etag": `etag_${index}`,
      "timeCreated": new Date(Date.now() - (1000000 * index)).toISOString(),
      "updated": new Date(Date.now() - (1000000 * index)).toISOString(),
      "timeStorageClassUpdated": new Date(Date.now() - (1000000 * index)).toISOString()
    });
  }
  return objects;
};

const PAGE_SIZE = 5; // Number of objects per page
const TOTAL_OBJECTS = 15; // Total number of objects to simulate

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

// Google Cloud Storage API-style cursor pagination endpoint
app.get('/storage/v1/b/:bucket/o', (req, res) => {
  const pageToken = req.query.pageToken || '';
  console.log(`[${new Date().toISOString()}] GET /storage/v1/b/${req.params.bucket}/o?pageToken=${pageToken}`);
  
  // Decode page token to get starting index (empty token means start from 0)
  let startIndex = 0;
  if (pageToken && pageToken !== '') {
    try {
      // Simple base64 decode for demo purposes
      startIndex = parseInt(Buffer.from(pageToken, 'base64').toString('utf-8'));
    } catch (e) {
      startIndex = 0;
    }
  }
  
  // Generate sample objects for this page
  const items = generateSampleObjects(startIndex, Math.min(PAGE_SIZE, TOTAL_OBJECTS - startIndex));
  
  // Calculate next page token
  const nextIndex = startIndex + PAGE_SIZE;
  const hasMorePages = nextIndex < TOTAL_OBJECTS;
  const nextPageToken = hasMorePages ? Buffer.from(nextIndex.toString()).toString('base64') : null;
  
  // Build response in Google Cloud Storage API format
  const response = {
    "kind": "storage#objects",
    "items": items
  };
  
  if (nextPageToken) {
    response.nextPageToken = nextPageToken;
  }
  
  console.log(`Returning ${items.length} items, startIndex: ${startIndex}, nextPageToken: ${nextPageToken || 'none'}`);
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
