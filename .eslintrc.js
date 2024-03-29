module.exports = {
  env: {
    browser: false,
    commonjs: true,
    es2020: true,
    node: true,
  },
  extends: 'eslint:recommended',
  parserOptions: {
    ecmaVersion: 11,
  },
  rules: {
    'no-debugger': 'warn',
  },
};
