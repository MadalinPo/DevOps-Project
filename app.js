const http = require('http');
const os = require('os');

// Application Versioning
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const ENVIRONMENT = process.env.ENVIRONMENT || 'blue';

// Simulation mode for demonstrating fault tolerance
const SIMULATE_FAILURE = process.env.SIMULATE_FAILURE === 'true';

const server = http.createServer((req, res) => {
  // Liveness and Readiness Probe
  if (req.url === '/health') {
    if (SIMULATE_FAILURE) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        status: 'unhealthy',
        version: APP_VERSION,
        environment: ENVIRONMENT,
        message: 'Simulated failure: Service unavailable'
      }));
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        status: 'healthy',
        version: APP_VERSION,
        environment: ENVIRONMENT,
        uptime: process.uptime()
      }));
    }
    return;
  }

  // Main endpoint
  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>Blue/Green Deployment Demo</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; }
          .container { max-width: 600px; margin: 0 auto; }
          .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
          .blue { background-color: #e3f2fd; border-left: 4px solid #1976d2; }
          .green { background-color: #e8f5e9; border-left: 4px solid #388e3c; }
          h1 { color: #333; }
          .info { background-color: #f5f5f5; padding: 15px; border-radius: 3px; }
          code { background-color: #eee; padding: 2px 6px; border-radius: 3px; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Blue/Green Deployment Implementation</h1>
          
          <div class="status ${ENVIRONMENT === 'blue' ? 'blue' : 'green'}">
            <h2>Current Environment: <strong>${ENVIRONMENT.toUpperCase()}</strong></h2>
            <p><strong>Version:</strong> ${APP_VERSION}</p>
            <p><strong>Hostname:</strong> ${os.hostname()}</p>
            <p><strong>Uptime:</strong> ${Math.floor(process.uptime())} seconds</p>
            ${SIMULATE_FAILURE ? '<p style="color: red;"><strong>Failure Simulation Active</strong></p>' : ''}
          </div>

          <div class="info">
            <h3>Endpoints Available:</h3>
            <ul>
              <li><code>GET /</code> - This page</li>
              <li><code>GET /health</code> - Health check endpoint</li>
              <li><code>GET /api/status</code> - JSON status endpoint</li>
              <li><code>GET /api/version</code> - Version information</li>
            </ul>
          </div>
        </div>
      </body>
      </html>
    `);
    return;
  }

  // JSON status endpoint
  if (req.url === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      environment: ENVIRONMENT,
      version: APP_VERSION,
      hostname: os.hostname(),
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      node_version: process.version
    }));
    return;
  }

  // Version endpoint
  if (req.url === '/api/version') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      version: APP_VERSION,
      environment: ENVIRONMENT
    }));
    return;
  }

  // 404
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] Server running on port ${PORT}`);
  console.log(`Environment: ${ENVIRONMENT}`);
  console.log(`Version: ${APP_VERSION}`);
  console.log(`Failure simulation: ${SIMULATE_FAILURE ? 'ENABLED' : 'disabled'}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});
