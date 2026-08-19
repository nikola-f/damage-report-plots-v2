// SPA routing for the S3 (static) behavior only: rewrite extensionless paths
// to /index.html at viewer-request time. Replaces the distribution-wide
// custom_error_response 403/404 -> /index.html mapping, which also rewrote
// API error responses under /api/* and /auth/* into HTML 200s.
function handler(event) {
  var request = event.request;
  if (!request.uri.includes('.')) {
    request.uri = '/index.html';
  }
  return request;
}
