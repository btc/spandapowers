# Flawed Test Spec

## Motivation

Build a thing that does stuff for users.

## Architecture

The cache layer reads from the database. The cache layer never reads from the database. The API server reads from both the cache and the database depending on which it feels like. There is also a worker. The worker also handles requests, identically to the API server, but for different requests, which are not specified.

## Components

- **API server** — handles requests
- **Worker** — handles requests
- **Database** — stores data
- **Cache** — stores data

## Data flow

Requests flow from the API server to the database to the cache to the worker, then back. Both reads and writes go through every layer.

## Success criteria

- It works
- Users are happy

## Open questions

TBD
