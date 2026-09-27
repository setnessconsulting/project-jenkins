#!/usr/bin/env node
// Fail-closed command line for the trusted Jenkins Test Platform adapter.
//
// Subcommands:
//   verify   <request.json>                       validate and resolve approved executors
//   finalize <request.json> <results.json> [out]  build a normalized receipt submission
//
// Every subcommand exits non-zero with a bounded diagnostic and writes nothing
// on rejection. No subcommand accepts a command, a credential, or any
// repository-controlled instruction.

import { readFileSync, writeFileSync } from 'node:fs';

import { ContractRejection, buildSubmission, loadApprovedCatalog, verifyRequest } from './adapter.mjs';

const USAGE = `usage:
  test-platform-contract verify <request.json>
  test-platform-contract finalize <request.json> <results.json> [submission.json]
`;

function readJson(path, label) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    throw new ContractRejection('unreadable-input', `${label} could not be read: ${error.code}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ContractRejection('malformed-document', `${label} is not valid JSON`);
  }
}

function emit(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function main(argv) {
  const [command, ...rest] = argv;
  if (command === 'help' || command === '--help' || command === undefined) {
    process.stdout.write(USAGE);
    return 0;
  }

  const catalog = loadApprovedCatalog();

  if (command === 'verify') {
    if (rest.length !== 1) throw new ContractRejection('usage', USAGE.trim());
    emit(verifyRequest(readJson(rest[0], 'request'), catalog));
    return 0;
  }

  if (command === 'finalize') {
    if (rest.length < 2 || rest.length > 3) {
      throw new ContractRejection('usage', USAGE.trim());
    }
    const request = readJson(rest[0], 'request');
    const results = readJson(rest[1], 'executor results');
    const submission = buildSubmission(request, results, {
      catalog,
      evidenceOrigin: request.execution_mode === 'controller-execution' ? 'controller-recorded' : 'synthetic',
      generatedAt: new Date().toISOString(),
    });
    const text = `${JSON.stringify(submission, null, 2)}\n`;
    if (rest.length === 3) {
      writeFileSync(rest[2], text, 'utf8');
      emit({ accepted: true, written: rest[2], outcomes: submission.outcomes.length });
    } else {
      process.stdout.write(text);
    }
    return 0;
  }

  throw new ContractRejection('usage', USAGE.trim());
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  if (error instanceof ContractRejection) {
    process.stderr.write(`${JSON.stringify({ accepted: false, code: error.code, message: error.message })}\n`);
    process.exitCode = 2;
  } else {
    throw error;
  }
}
