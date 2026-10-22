'use strict';

function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

function validatePaymentAmount(amount) {
  if (typeof amount !== 'number' || isNaN(amount)) {
    throw new Error('Amount must be a number');
  }
  if (amount <= 0) {
    throw new Error('Amount must be positive');
  }
  return true;
}

module.exports = { add, subtract, validatePaymentAmount };
