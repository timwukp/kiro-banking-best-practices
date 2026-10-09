module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testMatch: ['<rootDir>/test/**/*.test.ts'],
  // Compiled output and synthesized assemblies are never test inputs.
  modulePathIgnorePatterns: ['<rootDir>/build/', '<rootDir>/cdk.out/'],
  transform: {
    '^.+\\.tsx?$': 'ts-jest'
  }
};
