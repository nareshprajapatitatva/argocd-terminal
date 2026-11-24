const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

// Health check endpoints for Kubernetes probes
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/readyz', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

// Main Hello World API endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello World from Node.js on Kubernetes managed by ArgoCD!',
    environment: process.env.NODE_ENV || 'development',
    hostname: process.env.HOSTNAME || 'localhost',
    version: '1.0.0'
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
