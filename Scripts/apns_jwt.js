#!/usr/bin/env node
/**
 * Signs an APNs provider token (ES256 JWT) and prints it to stdout.
 *
 * Used by push_spike.sh. Node rather than openssl because `openssl dgst -sign` emits a
 * DER signature and JWS ES256 requires raw r||s -- Node's `dsaEncoding: 'ieee-p1363'`
 * gives that directly, with no ASN.1 surgery in bash.
 *
 * The production path does not use this file: the Edge Function signs with npm:jose.
 *
 * Usage: node apns_jwt.js <p8-path> <key-id> <team-id>
 */

const crypto = require('node:crypto');
const fs = require('node:fs');

const [, , keyPath, keyId, teamId] = process.argv;

if (!keyPath || !keyId || !teamId) {
  console.error('usage: node apns_jwt.js <p8-path> <key-id> <team-id>');
  process.exit(2);
}

const base64url = (input) =>
  Buffer.from(input).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
// APNs wants iss and iat. No exp -- the token is valid for one hour by APNs' own rule.
const claims = base64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
const signingInput = `${header}.${claims}`;

const signature = crypto
  .createSign('SHA256')
  .update(signingInput)
  .sign({ key: fs.readFileSync(keyPath, 'utf8'), dsaEncoding: 'ieee-p1363' });

process.stdout.write(
  `${signingInput}.${signature.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')}`
);
