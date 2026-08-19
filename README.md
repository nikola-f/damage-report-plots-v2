# damage-report-plots-v2

[![Terraform CI](https://github.com/nikola-f/damage-report-plots-v2/actions/workflows/ci-terraform.yml/badge.svg)](https://github.com/nikola-f/damage-report-plots-v2/actions/workflows/ci-terraform.yml)
[![Web CI](https://github.com/nikola-f/damage-report-plots-v2/actions/workflows/ci-web.yml/badge.svg)](https://github.com/nikola-f/damage-report-plots-v2/actions/workflows/ci-web.yml)


## Architecture

The pipeline runs **entirely in the browser**: the SPA talks to Google directly
(GIS token model, PKCE, no client secret) and no Gmail data ever reaches a
server. This avoids the CASA restricted-scope security assessment — the backend
that formerly ran the sync (ALB / ECS / Sidekiq / SQS / ElastiCache) has been
decommissioned, and only static hosting (S3 + CloudFront) remains.

### System Overview

```mermaid
graph TB
    subgraph AWS["AWS (static hosting only)"]
        S3["S3 (SPA bundle)"]
        CF["CloudFront"]
    end

    subgraph Google
        GIS["Google Identity Services\n(token model, PKCE)"]
        Gmail["Gmail API"]
        Sheets["Google Sheets API"]
        Drive["Drive API\n(drive.file discovery)"]
    end

    subgraph Client["Browser"]
        Web["apps/web (React SPA)"]
        IITC["apps/iitc (heatmap plugin)"]
    end

    CF -->|serve bundle| Web
    S3 -.->|origin| CF
    Web -->|OAuth token| GIS
    Web -->|list + batch get threads| Gmail
    Web -->|discover / create sheet| Drive
    Web -->|append rows / read plots| Sheets
    Web -->|copy plots JSON| IITC
```

### In-browser sync flow

```mermaid
graph TD
    Login["GIS login (profile gmail.readonly drive.file)"]
    Discover["Discover own Sheet via Drive appProperties marker"]
    Scan["Windowed Gmail scan\n(threads.list + batch threads.get)"]
    Parse["Parse HTML (DOMParser + XPath)\ndedupe / aggregate"]
    Append["Append rows to the user's Google Sheet"]
    Copy["Copy plots JSON to clipboard"]
    Render["IITC pastes JSON → renders heatmap"]

    Login --> Discover
    Discover --> Scan
    Scan --> Parse
    Parse --> Append
    Append --> Copy
    Copy --> Render
```

- **`apps/web`** — React SPA: auth, in-browser Gmail sync, Sheet write, and
  "Copy plots JSON" to the clipboard.
- **`apps/iitc`** — IITC plugin: pastes the plots JSON and renders the heatmap.
