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

const INITIAL_OBJECTS = 15; // Initial number of objects available

// Continuously and randomly add more objects after the initial set
let currentTotalObjects = INITIAL_OBJECTS;
const GROWTH_INTERVAL_MS = 5000; // every 5 seconds
const MIN_NEW_OBJECTS = 1; // at least 1 new object per interval
const MAX_NEW_OBJECTS = 5; // up to 5 new objects per interval

setInterval(() => {
  const add = Math.floor(Math.random() * (MAX_NEW_OBJECTS - MIN_NEW_OBJECTS + 1)) + MIN_NEW_OBJECTS;
  currentTotalObjects += add;
  console.log(`[${new Date().toISOString()}] Added ${add} new objects. Total now: ${currentTotalObjects}`);
}, GROWTH_INTERVAL_MS);


// Sample data for Elasticsearch search_after pagination with time-based document generation
const INITIAL_TIMESTAMP = 1647948000000;
const PAGE_SIZE = 3; // Number of documents per page (matching the example: 3 docs)
const DOCUMENTS_PER_INTERVAL = 3; // Generate 3 new documents every 5 seconds
const GENERATION_INTERVAL_MS = 5000; // 5 seconds

// Track when the server started to calculate available documents
const SERVER_START_TIME = Date.now();

const generateElasticsearchDocuments = (afterTime, pageSize) => {
  const hits = [];
  const startTime = afterTime || INITIAL_TIMESTAMP;
  
  // Calculate how many documents should be available based on elapsed time
  const elapsedSeconds = Math.floor((Date.now() - SERVER_START_TIME) / GENERATION_INTERVAL_MS);
  const maxAvailableDocuments = (elapsedSeconds + 1) * DOCUMENTS_PER_INTERVAL;
  const maxAvailableTimestamp = INITIAL_TIMESTAMP + (maxAvailableDocuments * 1000);
  
  console.log(`Elapsed intervals: ${elapsedSeconds}, Max available documents: ${maxAvailableDocuments}, Max timestamp: ${maxAvailableTimestamp}`);
  
  for (let i = 0; i < pageSize; i++) {
    const timestamp = startTime + (i * 1000) + 1000; // Increment by 1 second for each doc
    
    // Only return documents that should be "available" based on time elapsed
    if (timestamp > maxAvailableTimestamp) {
      console.log(`Document with timestamp ${timestamp} not yet available (max: ${maxAvailableTimestamp})`);
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
      "sort": [timestamp]
    });
  }
  
  console.log(`Returning ${hits.length} documents`);
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

  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${JSON.stringify(response)}`); 
  console.log(`Returning ${hits.length} documents, last sort value: ${lastSortValue}`);
  
  res.status(200).json(response);
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
  
  // Determine how many items are currently available, respecting dynamic growth
  const endIndexExclusive = Math.min(startIndex + PAGE_SIZE, currentTotalObjects);
  const availableCount = Math.max(0, endIndexExclusive - startIndex);

  // Generate sample objects for this page window
  const items = generateSampleObjects(startIndex, availableCount);

  // Calculate next page token based on current availability
  const hasMorePages = endIndexExclusive < currentTotalObjects;
  const nextPageToken = hasMorePages ? Buffer.from(endIndexExclusive.toString()).toString('base64') : null;
  
  // Build response in Google Cloud Storage API format
  const response = {
    "kind": "storage#objects",
    "items": items
  };
  
  if (nextPageToken) {
    response.nextPageToken = nextPageToken;
  }

  console.log("headers:");
  console.log(req.headers);
  console.log("body:");
  console.log(req.body);
  console.log(`[${new Date().toISOString()}] sending back ${JSON.stringify(response)}`); 
  console.log(`Returning ${items.length} items, startIndex: ${startIndex}, endIndex: ${endIndexExclusive}, currentTotal: ${currentTotalObjects}, nextPageToken: ${nextPageToken || 'none'}`);
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

app.listen(9006, () => console.log('Server running...'));
