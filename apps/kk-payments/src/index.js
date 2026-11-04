'use strict';
const express = require('express');
const pkg = require('../package.json');

const app = express();
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', version: pkg.version });
});

if (process.env.NODE_ENV !== 'test') {
  const PORT = process.env.PORT || 3001;
  app.listen(PORT, () => console.log(`Server on ${PORT}`));
}
module.exports = { app };
