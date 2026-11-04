'use strict';

const express = require('express');
const pkg = require('../package.json');

function add(a, b) { return a + b; }
function subtract(a, b) { return a - b; }
function validatePaymentAmount(amount) {
  if (typeof amount !== 'number' || isNaN(amount)) throw new Error('Amount must be a number');
  if (amount <= 0) throw new Error('Amount must be positive');
  return true;
}

const app = express();

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    version: process.env.APP_VERSION || pkg.version
  });
});

if (process.env.NODE_ENV !== 'test') {
  const PORT = process.env.PORT || 3001;
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}

module.exports = { add, subtract, validatePaymentAmount, app };
