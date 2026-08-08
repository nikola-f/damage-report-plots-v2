// Injectable fetch type shared across the sync modules so tests can supply a
// stub without touching the network.
export type FetchLike = typeof fetch;
