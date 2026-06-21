import type { WorkspaceWorkEvidence, WorkspaceWorkReport, WorkspaceWorkTrustSummary } from "@ctx/types";

const label = (value: string | null | undefined) =>
  String(value ?? "unknown").replaceAll("_", " ");

const shortSha = (value: string | null | undefined) => {
  if (!value) return "unknown";
  return value.length > 12 ? value.slice(0, 12) : value;
};

const trustClass = (verdict: string) => `work-report-trust work-report-trust-${verdict}`;

const evidenceClass = (item: WorkspaceWorkEvidence) =>
  `work-report-evidence-row work-report-evidence-${item.status} work-report-freshness-${item.freshness}`;

function TrustStrip({ trust }: { trust: WorkspaceWorkTrustSummary }) {
  return (
    <section className={trustClass(trust.verdict)} aria-label="Work trust">
      <div>
        <span className="work-report-eyebrow">Trust</span>
        <strong>{label(trust.verdict)}</strong>
      </div>
      <p>{trust.reason}</p>
      <div className="work-report-next">{trust.recommended_next_action}</div>
    </section>
  );
}

export function WorkReportView({ report, onRefresh }: { report: WorkspaceWorkReport; onRefresh?: () => void }) {
  const title = report.work.title || "Untitled Work";
  const hasEvidence = report.evidence.length > 0;
  const hasTimeline = report.timeline.length > 0;
  return (
    <main className="work-report-page">
      <header className="work-report-header">
        <div>
          <span className="work-report-eyebrow">Work Record</span>
          <h1>{title}</h1>
          <div className="work-report-meta">
            <span>{report.work.work_id}</span>
            <span>{label(report.work.lifecycle)}</span>
            <span>{report.work.primary_branch || "branch unknown"}</span>
            <span>{shortSha(report.work.head_commit)}</span>
          </div>
        </div>
        {onRefresh ? (
          <button className="work-report-refresh" type="button" onClick={onRefresh}>
            Refresh
          </button>
        ) : null}
      </header>

      <TrustStrip trust={report.trust} />

      {report.duplicate_strong_links.length > 0 ? (
        <section className="work-report-warning" aria-label="Duplicate Work links">
          <strong>Merge-needed links</strong>
          {report.duplicate_strong_links.map((item) => (
            <p key={`${item.target_kind}:${item.target_id}`}>
              {label(item.target_kind)} {item.target_id} is linked to {item.work_ids.length} Work records.
            </p>
          ))}
        </section>
      ) : null}

      <section className="work-report-summary-grid" aria-label="Evidence summary">
        <div>
          <span className="work-report-eyebrow">Evidence</span>
          <strong>{report.evidence_summary.total}</strong>
        </div>
        <div>
          <span className="work-report-eyebrow">Passing</span>
          <strong>{report.evidence_summary.passing}</strong>
        </div>
        <div>
          <span className="work-report-eyebrow">Failing</span>
          <strong>{report.evidence_summary.failing}</strong>
        </div>
        <div>
          <span className="work-report-eyebrow">Stale</span>
          <strong>{report.evidence_summary.stale}</strong>
        </div>
        <div>
          <span className="work-report-eyebrow">Summaries</span>
          <strong>{label(report.work.summary_freshness)}</strong>
        </div>
        <div>
          <span className="work-report-eyebrow">Changes</span>
          <strong>{report.change_summary.change_sets}</strong>
        </div>
      </section>

      <div className="work-report-layout">
        <section className="work-report-panel work-report-evidence" aria-label="Evidence">
          <div className="work-report-panel-header">
            <h2>Evidence</h2>
            <span>{hasEvidence ? `${report.evidence.length} observed` : "none recorded"}</span>
          </div>
          {hasEvidence ? (
            <div className="work-report-evidence-list">
              {report.evidence.map((item) => (
                <article className={evidenceClass(item)} key={item.evidence_id}>
                  <div>
                    <strong>{item.claim || item.command || item.evidence_id}</strong>
                    <p>{item.command || item.argv.join(" ")}</p>
                  </div>
                  <div className="work-report-evidence-badges">
                    <span>{label(item.kind)}</span>
                    <span>{label(item.status)}</span>
                    <span>{label(item.freshness)}</span>
                  </div>
                </article>
              ))}
            </div>
          ) : (
            <p className="work-report-empty">No evidence has been recorded for this Work record.</p>
          )}
        </section>

        <aside className="work-report-panel work-report-side" aria-label="Context and citations">
          <h2>Context</h2>
          {report.summaries.length > 0 ? (
            report.summaries.slice(0, 4).map((summary) => (
              <article className="work-report-summary" key={summary.summary_id}>
                <div className="work-report-meta">
                  <span>{label(summary.kind)}</span>
                  <span>{label(summary.freshness)}</span>
                </div>
                <p>{summary.text}</p>
              </article>
            ))
          ) : (
            <p className="work-report-empty">No summary has been generated yet.</p>
          )}
          <div className="work-report-raw-note">
            Raw transcripts are not included in this report response.
          </div>
        </aside>
      </div>

      <section className="work-report-panel work-report-timeline" aria-label="Timeline">
        <div className="work-report-panel-header">
          <h2>Timeline</h2>
          <span>{hasTimeline ? `${report.timeline.length} events` : "none recorded"}</span>
        </div>
        {hasTimeline ? (
          <ol>
            {report.timeline.slice(0, 50).map((event) => (
              <li key={event.event_id}>
                <span>{label(event.event_type)}</span>
                <time dateTime={event.event_time}>{new Date(event.event_time).toLocaleString()}</time>
                {event.redacted_text ? <p>{event.redacted_text}</p> : null}
              </li>
            ))}
          </ol>
        ) : (
          <p className="work-report-empty">No timeline events are available.</p>
        )}
      </section>
    </main>
  );
}
