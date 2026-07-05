// Pre-login explainer: a one-line tagline plus a Gmail → Parse → Sheets
// pipeline diagram, so first-time visitors see what the app does before
// granting any access.

const ICON_SIZE = 36;

function GmailIcon() {
  return (
    <svg
      className="pipeline-icon"
      width={ICON_SIZE}
      height={ICON_SIZE}
      viewBox="0 0 36 36"
      aria-hidden="true"
    >
      <rect
        x="4.5"
        y="9"
        width="27"
        height="18"
        rx="2.5"
        fill="none"
        stroke="var(--muted)"
        strokeWidth="2"
      />
      <path
        d="M6 11.5 L18 20 L30 11.5"
        fill="none"
        stroke="var(--muted)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ParseIcon() {
  return (
    <svg
      className="pipeline-icon"
      width={ICON_SIZE}
      height={ICON_SIZE}
      viewBox="0 0 36 36"
      aria-hidden="true"
    >
      <g
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {/* Angle brackets around a slash: "extract structured data from text". */}
        <path d="M12 10 L5 18 L12 26" />
        <path d="M24 10 L31 18 L24 26" />
        <path d="M20.5 8.5 L15.5 27.5" />
      </g>
    </svg>
  );
}

function PlotsIcon() {
  return (
    <svg
      className="pipeline-icon"
      width={ICON_SIZE}
      height={ICON_SIZE}
      viewBox="0 0 36 36"
      aria-hidden="true"
    >
      <g fill="none" stroke="var(--muted)" strokeWidth="1.5" strokeLinecap="round">
        <path d="M6 4.5 V31.5" />
        <path d="M4.5 30 H31.5" />
      </g>
      {/* Same dots as public/favicon.svg, scaled onto the axes. */}
      <circle cx="13" cy="23" r="3.5" fill="#00c5ff" />
      <circle cx="20" cy="12.5" r="3" fill="#03fe03" />
      <circle cx="27" cy="19" r="2.5" fill="#5ab5b2" />
    </svg>
  );
}

function Arrow() {
  return (
    <svg
      className="pipeline-arrow"
      width="20"
      height="20"
      viewBox="0 0 20 20"
      aria-hidden="true"
    >
      <path
        d="M3 10 H16 M11.5 5 L16.5 10 L11.5 15"
        fill="none"
        stroke="var(--muted)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export default function HowItWorks() {
  return (
    <section className="how-it-works">
      <p className="tagline">
        Turn damage report emails into portal plots on a Google Sheet.
      </p>
      <div className="pipeline">
        <div className="pipeline-step">
          <GmailIcon />
          <span className="pipeline-label">Gmail</span>
          <span className="pipeline-caption">Damage report emails</span>
        </div>
        <Arrow />
        <div className="pipeline-step">
          <ParseIcon />
          <span className="pipeline-label">Parse</span>
          <span className="pipeline-caption">Extract portal names &amp; coordinates</span>
        </div>
        <Arrow />
        <div className="pipeline-step">
          <PlotsIcon />
          <span className="pipeline-label">Sheets</span>
          <span className="pipeline-caption">Appended to your Google Sheet</span>
        </div>
      </div>
    </section>
  );
}
