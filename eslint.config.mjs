// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import js from '@eslint/js';
import globals from 'globals';

export default [
  {
    files: ['backend/**/*.mjs', 'tests/**/*.mjs', 'eslint.config.mjs'],
    languageOptions: { ecmaVersion: 'latest', sourceType: 'module', globals: globals.node },
    rules: {
      ...js.configs.recommended.rules,
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
];
