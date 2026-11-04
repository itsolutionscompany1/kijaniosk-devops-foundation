'use strict';

const { add, subtract, validatePaymentAmount } = require('../src/index');

describe('math', () => {
  test('add works', () => {
    expect(add(2, 3)).toBe(5);
  });
  test('subtract works', () => {
    expect(subtract(5, 3)).toBe(2);
  });
});

describe('validatePaymentAmount', () => {
  test('accepts positive numbers', () => {
    expect(validatePaymentAmount(10)).toBe(true);
  });
  test('rejects zero', () => {
    expect(() => validatePaymentAmount(0)).toThrow();
  });
  test('rejects negative', () => {
    expect(() => validatePaymentAmount(-5)).toThrow();
  });
  test('rejects non-number', () => {
    expect(() => validatePaymentAmount('10')).toThrow();
  });
});
