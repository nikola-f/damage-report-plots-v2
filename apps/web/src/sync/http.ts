// Injectable fetch type shared across the sync modules so tests can supply a
// stub without touching the network.
export type FetchLike = typeof fetch;

// Default fetch bound to the global scope. A bare `fetch` reference passed
// around and later called as `fetchFn(...)` loses its `this`, which throws
// "Illegal invocation" (notably inside a Web Worker). Calling it as a method of
// globalThis keeps the binding, and staying lazy avoids touching fetch at import
// time.
export const defaultFetch: FetchLike = (input, init) => globalThis.fetch(input, init);
