const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Docker Workflow Optimizer Demo',
    performance: {
      build_improvement: '80%',
      size_reduction: '60%',
      deployment_speed: '70%'
    },
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
});
