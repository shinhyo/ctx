import React, { useMemo, useState } from "react";
import ReactDOM from "react-dom/client";
import * as Tabs from "@radix-ui/react-tabs";
import { ColumnDef, flexRender, getCoreRowModel, useReactTable } from "@tanstack/react-table";
import {
  Activity,
  AlertTriangle,
  Archive,
  Bot,
  CheckCircle2,
  Clock3,
  Command,
  Database,
  FileText,
  GitBranch,
  GitPullRequest,
  MessageSquareText,
  Monitor,
  Moon,
  RefreshCw,
  Search,
  Settings,
  ShieldCheck,
  Sun,
  Terminal,
  Workflow,
  Wrench
} from "lucide-react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { clsx } from "clsx";
import { readDashboardData } from "./data";
import type {
  DashboardData,
  DashboardEvent,
  DashboardRecord,
  DashboardRun,
  DashboardSession,
  EvidenceCommand
} from "./types";
import "./styles.css";

const data = readDashboardData();

function App() {
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const [query, setQuery] = useState("");
  const [activeTab, setActiveTab] = useState("overview");
  const failedCommands = data.commands.filter((command) => command.exit_code !== 0).length;
  const linkedPrUrls = uniquePullRequestUrls(data);
  const providers = providerSummaries(data);

  React.useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.classList.toggle("dark", theme === "dark");
  }, [theme]);

  React.useEffect(() => {
    const activeTrigger = document.querySelector<HTMLButtonElement>(`[data-dashboard-tab="${activeTab}"]`);
    const tabList = activeTrigger?.closest<HTMLElement>(".tab-list");
    if (!activeTrigger || !tabList) return;

    const scrollActiveTab = () => {
      activeTrigger.scrollIntoView({ block: "nearest", inline: "center", behavior: "instant" });
    };

    scrollActiveTab();
    requestAnimationFrame(scrollActiveTab);
  }, [activeTab]);

  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="border-b border-border bg-card">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 px-4 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
          <div className="min-w-0">
            <div className="flex items-center gap-2 text-sm font-medium text-muted-foreground">
              <Monitor className="size-4" aria-hidden />
              <span>Local Work Recorder</span>
              <span className="rounded-sm border border-border px-1.5 py-0.5 text-xs">{data.status.javascript_app}</span>
            </div>
            <h1 className="mt-1 text-2xl font-semibold tracking-normal sm:text-3xl">Work Records</h1>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <StatusPill tone={data.share_safe ? "ok" : "warn"} icon={<ShieldCheck className="size-3.5" />}>
              Share-safe export
            </StatusPill>
            {failedCommands > 0 ? (
              <StatusPill tone="danger" icon={<AlertTriangle className="size-3.5" />}>
                {failedCommands} failing command{failedCommands === 1 ? "" : "s"}
              </StatusPill>
            ) : (
              <StatusPill tone="ok" icon={<CheckCircle2 className="size-3.5" />}>Evidence passing</StatusPill>
            )}
            <button
              className="icon-button"
              title={theme === "dark" ? "Use light theme" : "Use dark theme"}
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              type="button"
            >
              {theme === "dark" ? <Sun className="size-4" /> : <Moon className="size-4" />}
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-4 py-5 sm:px-6">
        <div className="mb-5 grid gap-3 md:grid-cols-5">
          <Metric label="Records" value={data.summary.record_count} />
          <Metric label="Evidence" value={data.summary.evidence_count} />
          <Metric label="Providers" value={providers.length} />
          <Metric label="Linked PRs" value={linkedPrUrls.length} />
          <Metric label="Raw transcripts withheld" value={data.privacy.raw_transcripts_withheld} />
        </div>

        <Tabs.Root value={activeTab} onValueChange={setActiveTab} className="space-y-4">
          <Tabs.List className="tab-list" aria-label="Dashboard views">
            <Tab value="overview" icon={<Activity className="size-4" />} label="Overview" />
            <Tab value="workspace" icon={<GitBranch className="size-4" />} label="Workspace" />
            <Tab value="session" icon={<Bot className="size-4" />} label="Providers" />
            <Tab value="evidence" icon={<ShieldCheck className="size-4" />} label="PR/Evidence" />
            <Tab value="search" icon={<Search className="size-4" />} label="Search" />
            <Tab value="settings" icon={<Settings className="size-4" />} label="Status" />
          </Tabs.List>

          <Tabs.Content value="overview">
            <Overview data={data} />
          </Tabs.Content>
          <Tabs.Content value="workspace">
            <WorkspaceView data={data} />
          </Tabs.Content>
          <Tabs.Content value="session">
            <SessionView data={data} />
          </Tabs.Content>
          <Tabs.Content value="evidence">
            <EvidenceView data={data} />
          </Tabs.Content>
          <Tabs.Content value="search">
            <SearchView data={data} query={query} setQuery={setQuery} />
          </Tabs.Content>
          <Tabs.Content value="settings">
            <SettingsView data={data} />
          </Tabs.Content>
        </Tabs.Root>
      </main>
    </div>
  );
}

function Tab({ value, icon, label }: { value: string; icon: React.ReactNode; label: string }) {
  return (
    <Tabs.Trigger className="tab-trigger" value={value} data-dashboard-tab={value}>
      {icon}
      <span>{label}</span>
    </Tabs.Trigger>
  );
}

function useMediaQuery(query: string) {
  const [matches, setMatches] = React.useState(false);

  React.useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const update = () => setMatches(mediaQuery.matches);
    update();
    mediaQuery.addEventListener("change", update);
    return () => mediaQuery.removeEventListener("change", update);
  }, [query]);

  return matches;
}

function Overview({ data }: { data: DashboardData }) {
  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(340px,1fr)]">
      <section className="panel">
        <SectionHeader icon={<FileText className="size-4" />} title="Recent Records" />
        <div className="record-list">
          {data.records.length === 0 ? (
            <EmptyState text="No Work Records found in the local store." />
          ) : (
            data.records.map((record) => <RecordRow key={record.id} record={record} />)
          )}
        </div>
      </section>
      <div className="space-y-4">
        <section className="panel">
          <SectionHeader icon={<Activity className="size-4" />} title="Work Mix" />
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={tagChartData(data)}>
                <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
                <XAxis dataKey="name" tickLine={false} axisLine={false} />
                <YAxis allowDecimals={false} tickLine={false} axisLine={false} />
                <Tooltip cursor={{ fill: "hsl(var(--muted))" }} />
                <Bar dataKey="count" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </section>
        <section className="panel">
          <SectionHeader icon={<ShieldCheck className="size-4" />} title="Share and Publish Preview" />
          <p className="text-sm text-muted-foreground">
            Static local export with redacted summaries, command previews, safe PR links, and raw transcript content withheld by default.
          </p>
          <div className="mt-3 grid gap-2 text-sm">
            <KeyValue label="Records" value={data.records.length} />
            <KeyValue label="Commands" value={data.commands.length} />
            <KeyValue label="Withheld raw transcripts" value={data.privacy.raw_transcripts_withheld} />
          </div>
        </section>
      </div>
    </div>
  );
}

function WorkspaceView({ data }: { data: DashboardData }) {
  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <section className="panel">
        <SectionHeader icon={<GitBranch className="size-4" />} title="Workspace / Repo" />
        {data.vcs_workspaces.length === 0 ? (
          <EmptyState text="No Git or jj state is available in this export." />
        ) : (
          <div className="space-y-3">
            {data.vcs_workspaces.map((workspace) => (
              <div className="row-card" key={String(workspace.id)}>
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="font-medium">{String(workspace.repo ?? workspace.root ?? "workspace")}</div>
                    <div className="truncate text-sm text-muted-foreground">{String(workspace.monorepo_subpath ?? workspace.root ?? "")}</div>
                  </div>
                  <span className="badge">{String(workspace.kind ?? "vcs")}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
      <section className="panel">
        <SectionHeader icon={<FileText className="size-4" />} title="Files Touched" />
        {data.files_touched.length === 0 ? (
          <EmptyState text="No file touch metadata is available in this export." />
        ) : (
          <div className="overflow-auto">
            <table className="data-table">
              <thead>
                <tr><th>Path</th><th>Change</th><th>Delta</th></tr>
              </thead>
              <tbody>
                {data.files_touched.map((file) => (
                  <tr key={String(file.id)}>
                    <td><code>{String(file.path ?? "")}</code></td>
                    <td>{String(file.change_kind ?? "unknown")}</td>
                    <td>{String(file.line_count_delta ?? "")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <section className="panel lg:col-span-2">
        <SectionHeader icon={<GitBranch className="size-4" />} title="Git and jj Changes" />
        {data.vcs_changes.length === 0 ? (
          <EmptyState text="No Git or jj changes are available in this export." />
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {data.vcs_changes.map((change) => (
              <div className="row-card" key={String(change.id)}>
                <div className="flex items-center gap-2">
                  <span className="badge">{String(change.kind ?? "change")}</span>
                  <code>{String(change.change_id ?? "")}</code>
                </div>
                <div className="mt-2 text-sm text-muted-foreground">{String(change.branch_or_bookmark ?? "detached")}</div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function SessionView({ data }: { data: DashboardData }) {
  const [selectedSessionId, setSelectedSessionId] = useState(() => sessionId(data.sessions[0]));

  React.useEffect(() => {
    if (selectedSessionId && data.sessions.some((session) => sessionId(session) === selectedSessionId)) return;
    setSelectedSessionId(sessionId(data.sessions[0]));
  }, [data.sessions, selectedSessionId]);

  const selectedSession = data.sessions.find((session) => sessionId(session) === selectedSessionId);
  const selectedEvents = selectedSessionId ? relatedBySession(data.events, selectedSessionId) : [];
  const selectedRuns = selectedSessionId ? relatedBySession(data.runs, selectedSessionId) : [];

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <ProviderSummaryPanel data={data} />
      <SessionPickerPanel
        data={data}
        selectedSessionId={selectedSessionId}
        setSelectedSessionId={setSelectedSessionId}
      />
      <SessionDetailPanel
        data={data}
        session={selectedSession}
        events={selectedEvents}
        runs={selectedRuns}
      />
      <section className="panel lg:col-span-2">
        <SectionHeader icon={<Command className="size-4" />} title="Command Evidence" />
        <CommandTable commands={data.commands} />
      </section>
    </div>
  );
}

function ProviderSummaryPanel({ data }: { data: DashboardData }) {
  const providers = providerSummaries(data);

  return (
    <section className="panel">
      <SectionHeader icon={<Bot className="size-4" />} title="Provider Coverage" />
      {providers.length === 0 ? (
        <EmptyState
          title="No provider sessions"
          text={providerSparseText(data)}
        />
      ) : (
        <div className="provider-grid">
          {providers.map((provider) => (
            <article className="provider-card" key={provider.provider}>
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="truncate font-semibold">{provider.provider}</div>
                  <div className="text-sm text-muted-foreground">{provider.sessions} session{provider.sessions === 1 ? "" : "s"}</div>
                </div>
                <span className="badge">{provider.events} event{provider.events === 1 ? "" : "s"}</span>
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                {provider.fidelities.map((fidelity) => <span className="badge" key={fidelity}>{fidelity}</span>)}
                {provider.statuses.map((status) => <span className="badge" key={status}>{status}</span>)}
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function SessionPickerPanel({
  data,
  selectedSessionId,
  setSelectedSessionId
}: {
  data: DashboardData;
  selectedSessionId: string;
  setSelectedSessionId: (value: string) => void;
}) {
  return (
    <section className="panel">
      <SectionHeader icon={<Workflow className="size-4" />} title="Provider Sessions" />
      {data.sessions.length === 0 ? (
        <EmptyState
          title="Session metadata unavailable"
          text={providerSparseText(data)}
        />
      ) : (
        <div className="session-list">
          {data.sessions.map((session) => {
            const id = sessionId(session);
            return (
              <button
                className={clsx("session-button", id === selectedSessionId && "session-button-active")}
                key={id}
                onClick={() => setSelectedSessionId(id)}
                type="button"
              >
                <div className="flex min-w-0 flex-1 flex-col gap-1 text-left">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="badge">{valueText(session.provider, "provider")}</span>
                    <span className="badge">{valueText(session.status, "status")}</span>
                    <span className="badge">{valueText(session.fidelity, "fidelity")}</span>
                  </div>
                  <span className="truncate text-sm text-muted-foreground">
                    {valueText(session.role_hint ?? session.agent_type ?? session.external_agent_id, "session")}
                  </span>
                </div>
                <Clock3 className="size-4 text-muted-foreground" aria-hidden />
              </button>
            );
          })}
        </div>
      )}
      {data.sessions.length === 0 && data.runs.length > 0 ? (
        <div className="mt-3 space-y-3">
          {data.runs.slice(0, 4).map((run) => (
            <div className="row-card" key={String(run.id)}>
              <div className="flex flex-wrap items-center gap-2">
                <Terminal className="size-4 text-muted-foreground" />
                <span className="font-medium">{valueText(run.command_preview ?? run.run_type, "run")}</span>
                <span className={clsx("badge", run.status === "succeeded" ? "badge-ok" : "badge-warn")}>{valueText(run.status, "unknown")}</span>
              </div>
            </div>
          ))}
        </div>
      ) : null}
    </section>
  );
}

function SessionDetailPanel({
  data,
  session,
  events,
  runs
}: {
  data: DashboardData;
  session: DashboardSession | undefined;
  events: DashboardEvent[];
  runs: DashboardRun[];
}) {
  const messages = events.filter((event) => String(event.event_type) === "message");
  const toolEvents = events.filter((event) => ["tool_call", "tool_output"].includes(String(event.event_type)));
  const summaries = session ? relatedBySession(data.summaries, sessionId(session)) : [];
  const linkedPrUrls = uniquePullRequestUrls(data);

  return (
    <section className="panel lg:col-span-2">
      <SectionHeader icon={<MessageSquareText className="size-4" />} title="Session Detail" />
      {!session ? (
        <EmptyState
          title="No session selected"
          text={providerSparseText(data)}
        />
      ) : (
        <div className="session-detail">
          <div className="detail-grid">
            <KeyValue label="Provider" value={valueText(session.provider, "provider")} />
            <KeyValue label="Status" value={valueText(session.status, "status")} />
            <KeyValue label="Fidelity" value={valueText(session.fidelity, "unknown")} />
            <KeyValue label="Role" value={valueText(session.role_hint ?? session.agent_type, "not provided")} />
            <KeyValue label="External session" value={valueText(session.external_session_id, "withheld or absent")} />
            <KeyValue label="Started" value={valueText(session.started_at, "unknown")} />
          </div>

          <DetailSection icon={<MessageSquareText className="size-4" />} title="Prompts and Messages">
            <EventList
              events={messages}
              emptyText="This provider session did not expose redacted prompt or assistant message events in this export."
            />
          </DetailSection>

          <DetailSection icon={<Wrench className="size-4" />} title="Tool Calls and Output">
            <EventList
              events={toolEvents}
              emptyText="No redacted tool-call or tool-output events are available for this session."
            />
          </DetailSection>

          <DetailSection icon={<Terminal className="size-4" />} title="Runs and Commands">
            <RunList runs={runs} />
          </DetailSection>

          <DetailSection icon={<Archive className="size-4" />} title="Artifacts, PR Links, and Freshness">
            <div className="detail-columns">
              <MiniList
                icon={<Archive className="size-3.5" />}
                title="Artifacts"
                items={data.artifacts.map((artifact) => `${valueText(artifact.kind, "artifact")} · ${valueText(artifact.redaction_state, "redacted")}`)}
                empty="No share-safe artifacts are linked in this export."
              />
              <MiniList
                icon={<GitPullRequest className="size-3.5" />}
                title="PR Links"
                items={linkedPrUrls}
                empty="No pull request links are available."
              />
              <MiniList
                icon={<RefreshCw className="size-3.5" />}
                title="Freshness"
                items={data.evidence_metadata.map((item) => `${valueText(item.kind, "evidence")} · ${valueText(item.status, "unknown")} · ${valueText(item.freshness, "unbound")}`)}
                empty="No typed freshness metadata is available."
              />
            </div>
          </DetailSection>

          {summaries.length > 0 ? (
            <DetailSection icon={<FileText className="size-4" />} title="Imported Summaries">
              <div className="event-list">
                {summaries.map((summary) => (
                  <article className="transcript-event" key={String(summary.id)}>
                    <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
                      <span className="badge">{valueText(summary.kind, "summary")}</span>
                      {summary.model_or_source ? <span className="badge">{valueText(summary.model_or_source)}</span> : null}
                    </div>
                    <p>{valueText(summary.text, "summary preview unavailable")}</p>
                  </article>
                ))}
              </div>
            </DetailSection>
          ) : null}
        </div>
      )}
    </section>
  );
}

function DetailSection({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <div className="detail-section">
      <div className="detail-section-title">
        {icon}
        <h3>{title}</h3>
      </div>
      {children}
    </div>
  );
}

function EventList({ events, emptyText }: { events: DashboardEvent[]; emptyText: string }) {
  if (events.length === 0) return <EmptyState text={emptyText} />;
  return (
    <div className="event-list">
      {events.map((event) => (
        <article className="transcript-event" key={String(event.id)}>
          <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
            {String(event.event_type).startsWith("tool") ? <Wrench className="size-3.5 text-muted-foreground" /> : <MessageSquareText className="size-3.5 text-muted-foreground" />}
            <span className="badge">{valueText(event.event_type, "event")}</span>
            {event.role ? <span className="badge">{valueText(event.role)}</span> : null}
            <span className="text-muted-foreground">#{valueText(event.seq, "0")}</span>
            <span className="badge">{valueText(event.redaction_state, "redacted")}</span>
          </div>
          <p>{valueText(event.preview, "raw event payload withheld")}</p>
        </article>
      ))}
    </div>
  );
}

function RunList({ runs }: { runs: DashboardRun[] }) {
  if (runs.length === 0) return <EmptyState text="No provider-linked run metadata is available. Command evidence may still appear below." />;
  return (
    <div className="event-list">
      {runs.map((run) => (
        <article className="transcript-event" key={String(run.id)}>
          <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
            <Terminal className="size-3.5 text-muted-foreground" />
            <span className="badge">{valueText(run.run_type, "run")}</span>
            <span className={clsx("badge", run.status === "succeeded" ? "badge-ok" : "badge-warn")}>{valueText(run.status, "unknown")}</span>
            {run.exit_code !== undefined && run.exit_code !== null ? <ExitBadge exitCode={Number(run.exit_code)} /> : null}
          </div>
          <p>{valueText(run.command_preview, "run preview unavailable")}</p>
        </article>
      ))}
    </div>
  );
}

function MiniList({ icon, title, items, empty }: { icon: React.ReactNode; title: string; items: string[]; empty: string }) {
  return (
    <div className="mini-list">
      <div className="mini-list-title">{icon}<span>{title}</span></div>
      {items.length === 0 ? (
        <p className="mini-list-empty">{empty}</p>
      ) : (
        <ul>
          {items.slice(0, 5).map((item) => <li key={item}>{item}</li>)}
        </ul>
      )}
    </div>
  );
}

function EvidenceView({ data }: { data: DashboardData }) {
  const linkedPrUrls = uniquePullRequestUrls(data);

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <section className="panel">
        <SectionHeader icon={<ShieldCheck className="size-4" />} title="Evidence Previews" />
        <CommandTable commands={data.commands} />
      </section>
      <section className="panel">
        <SectionHeader icon={<GitBranch className="size-4" />} title="PR Links" />
        {linkedPrUrls.length === 0 ? (
          <EmptyState text="No pull request links are available in this export." />
        ) : (
          <div className="space-y-3">
            {linkedPrUrls.map((url) => (
              <a className="link-row" href={url} key={url} rel="noreferrer">
                {url}
              </a>
            ))}
          </div>
        )}
      </section>
      <section className="panel">
        <SectionHeader icon={<Archive className="size-4" />} title="Artifacts" />
        {data.artifacts.length === 0 ? (
          <EmptyState text="No artifacts are available in this export." />
        ) : (
          <div className="space-y-3">
            {data.artifacts.map((artifact) => (
              <div className="row-card" key={String(artifact.id)}>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="badge">{String(artifact.kind ?? "artifact")}</span>
                  <span className="text-sm text-muted-foreground">{String(artifact.byte_size ?? 0)} bytes</span>
                  <span className="badge">{String(artifact.redaction_state ?? "redacted")}</span>
                </div>
                {artifact.preview ? <pre className="preview">{String(artifact.preview)}</pre> : null}
              </div>
            ))}
          </div>
        )}
      </section>
      <section className="panel">
        <SectionHeader icon={<AlertTriangle className="size-4" />} title="Evidence Status" />
        {data.evidence_metadata.length === 0 ? (
          <EmptyState text="No typed evidence metadata is available in this export." />
        ) : (
          <div className="space-y-3">
            {data.evidence_metadata.map((evidence) => {
              const tone = evidenceTone(evidence.status);
              return (
                <div className={clsx("row-card", tone === "danger" && "row-card-danger")} key={String(evidence.id)}>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="badge">{String(evidence.kind ?? "evidence")}</span>
                    <span className={clsx("badge", `badge-${tone}`)}>{String(evidence.status ?? "unknown")}</span>
                    <span className="text-sm text-muted-foreground">{String(evidence.freshness ?? "")}</span>
                  </div>
                  {evidence.stale_reason ? <p className="mt-2 text-sm text-muted-foreground">{String(evidence.stale_reason)}</p> : null}
                </div>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}

function SearchView({ data, query, setQuery }: { data: DashboardData; query: string; setQuery: (value: string) => void }) {
  const results = useMemo(() => {
    const term = query.trim().toLowerCase();
    const haystack = [
      ...data.records.map((record) => ({ type: "record", title: record.title, body: record.body, id: record.id })),
      ...data.commands.map((command) => ({ type: "command", title: command.command, body: command.output_preview ?? "", id: command.id })),
      ...data.events.map((event) => ({ type: "event", title: String(event.event_type), body: String(event.preview ?? ""), id: String(event.id) })),
      ...data.artifacts.map((artifact) => ({ type: "artifact", title: String(artifact.kind), body: String(artifact.preview ?? ""), id: String(artifact.id) }))
    ];
    if (!term) return haystack.slice(0, 12);
    return haystack.filter((item) => `${item.title} ${item.body}`.toLowerCase().includes(term)).slice(0, 20);
  }, [data, query]);

  return (
    <section className="panel">
      <SectionHeader icon={<Search className="size-4" />} title="Search / Explore" />
      <div className="search-box">
        <Search className="size-4 text-muted-foreground" />
        <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search records, commands, transcript previews, artifacts" />
      </div>
      <p className="mt-2 text-sm text-muted-foreground">CLI equivalent: <code>{data.status.search_command}</code></p>
      <div className="mt-4 space-y-3">
        {results.map((result) => (
          <div className="row-card" key={`${result.type}-${result.id}`}>
            <div className="mb-1 flex items-center gap-2">
              <span className="badge">{result.type}</span>
              <span className="truncate font-medium">{result.title}</span>
            </div>
            <p className="text-sm text-muted-foreground">{result.body || result.id}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function SettingsView({ data }: { data: DashboardData }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <section className="panel">
        <SectionHeader icon={<Settings className="size-4" />} title="Settings / Status" />
        <div className="grid gap-2 text-sm">
          <KeyValue label="Export mode" value={data.status.export_mode} />
          <KeyValue label="Dashboard app" value={data.status.javascript_app} />
          <KeyValue label="Data contract" value={data.status.data_contract} />
          <KeyValue label="Schema version" value={data.schema_version} />
          <KeyValue label="Local only" value={data.status.local_only ? "yes" : "no"} />
        </div>
      </section>
      <section className="panel">
        <SectionHeader icon={<Database className="size-4" />} title="Redaction and Privacy" />
        <div className="grid gap-2 text-sm">
          <KeyValue label="Default output" value={data.privacy.default_redacted ? "redacted/share-safe" : "not redacted"} />
          <KeyValue label="Raw transcripts withheld" value={data.privacy.raw_transcripts_withheld} />
          <KeyValue label="Redacted previews" value={data.privacy.redacted_previews} />
          <KeyValue label="Withheld links" value={data.privacy.withheld_links} />
          <KeyValue label="Local paths redacted" value={data.privacy.local_paths_redacted ? "yes" : "no"} />
        </div>
      </section>
    </div>
  );
}

function CommandTable({ commands }: { commands: EvidenceCommand[] }) {
  const isMobile = useMediaQuery("(max-width: 640px)");
  const columns = useMemo<ColumnDef<EvidenceCommand>[]>(
    () => [
      { accessorKey: "command", header: "Command", cell: (info) => <code>{String(info.getValue())}</code> },
      {
        accessorKey: "exit_code",
        header: "Exit",
        cell: (info) => {
          const exitCode = Number(info.getValue());
          return <ExitBadge exitCode={exitCode} />;
        }
      },
      { accessorKey: "duration_ms", header: "Duration" },
      { accessorKey: "output_preview", header: "Preview" }
    ],
    []
  );
  const table = useReactTable({ data: commands, columns, getCoreRowModel: getCoreRowModel() });
  if (commands.length === 0) return <EmptyState text="No evidence has been captured yet." />;
  if (isMobile) {
    return (
      <div className="command-card-list">
        {commands.map((command) => (
          <article className={clsx("command-card", command.exit_code !== 0 && "command-card-danger")} key={command.id}>
            <div className="command-card-command">
              <span>Command</span>
              <code>{command.command}</code>
            </div>
            <div className="command-card-meta">
              <KeyValue label="Exit" value={<ExitBadge exitCode={command.exit_code} />} />
              <KeyValue label="Duration" value={`${command.duration_ms}ms`} />
            </div>
            {command.output_preview ? (
              <div className="command-card-preview">
                <span>Preview</span>
                <p>{command.output_preview}</p>
              </div>
            ) : null}
          </article>
        ))}
      </div>
    );
  }

  return (
    <div className="table-scroll">
      <table className="data-table">
        <thead>
          {table.getHeaderGroups().map((headerGroup) => (
            <tr key={headerGroup.id}>
              {headerGroup.headers.map((header) => (
                <th key={header.id}>{flexRender(header.column.columnDef.header, header.getContext())}</th>
              ))}
            </tr>
          ))}
        </thead>
        <tbody>
          {table.getRowModel().rows.map((row) => (
            <tr className={row.original.exit_code !== 0 ? "data-row-danger" : undefined} key={row.id}>
              {row.getVisibleCells().map((cell) => (
                <td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function RecordRow({ record }: { record: DashboardRecord }) {
  return (
    <article className="row-card">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h2 className="truncate text-base font-semibold">{record.title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">{record.body}</p>
        </div>
        <span className="badge shrink-0">{record.kind}</span>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {record.workspace ? <span className="badge">{record.workspace}</span> : null}
        {record.tags.map((tag) => <span className="badge" key={tag}>#{tag}</span>)}
        {record.pr_url ? <a className="badge-link" href={record.pr_url} rel="noreferrer">PR</a> : null}
      </div>
    </article>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="metric">
      <div className="text-2xl font-semibold">{value}</div>
      <div className="mt-1 text-sm text-muted-foreground">{label}</div>
    </div>
  );
}

function SectionHeader({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div className="mb-3 flex items-center gap-2">
      <div className="section-icon">{icon}</div>
      <h2 className="text-base font-semibold">{title}</h2>
    </div>
  );
}

function StatusPill({ tone, icon, children }: { tone: "ok" | "warn" | "danger"; icon: React.ReactNode; children: React.ReactNode }) {
  return <span className={clsx("status-pill", `status-${tone}`)}>{icon}{children}</span>;
}

function ExitBadge({ exitCode }: { exitCode: number }) {
  return <span className={clsx("badge", exitCode === 0 ? "badge-ok" : "badge-danger")}>Exit {exitCode}</span>;
}

function EmptyState({ title, text }: { title?: string; text: string }) {
  return (
    <div className="empty-state">
      {title ? <strong>{title}</strong> : null}
      <span>{text}</span>
    </div>
  );
}

function KeyValue({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="key-value">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function tagChartData(data: DashboardData) {
  if (data.summary.tags.length > 0) {
    return data.summary.tags.slice(0, 6).map((tag) => ({ name: tag.tag, count: tag.count }));
  }
  return [
    { name: "records", count: data.records.length },
    { name: "commands", count: data.commands.length },
    { name: "events", count: data.events.length }
  ];
}

function uniquePullRequestUrls(data: DashboardData) {
  return Array.from(
    new Set(
      [
        ...data.pull_requests.map((pr) => pr.url),
        ...data.records.map((record) => record.pr_url)
      ].filter((url): url is string => typeof url === "string" && url.trim().length > 0)
    )
  );
}

function providerSummaries(data: DashboardData) {
  const summaries = new Map<string, {
    provider: string;
    sessions: number;
    events: number;
    runs: number;
    fidelities: string[];
    statuses: string[];
  }>();

  for (const session of data.sessions) {
    const provider = valueText(session.provider, "unknown");
    const current = summaries.get(provider) ?? {
      provider,
      sessions: 0,
      events: 0,
      runs: 0,
      fidelities: [],
      statuses: []
    };
    const id = sessionId(session);
    current.sessions += 1;
    current.events += relatedBySession(data.events, id).length;
    current.runs += relatedBySession(data.runs, id).length;
    addUnique(current.fidelities, valueText(session.fidelity, "unknown"));
    addUnique(current.statuses, valueText(session.status, "unknown"));
    summaries.set(provider, current);
  }

  return Array.from(summaries.values()).sort((left, right) => left.provider.localeCompare(right.provider));
}

function addUnique(values: string[], value: string) {
  if (!values.includes(value)) values.push(value);
}

function sessionId(session: DashboardSession | undefined) {
  return session ? String(session.id ?? "") : "";
}

function relatedBySession<T extends Record<string, unknown>>(items: T[], id: string) {
  if (!id) return [];
  return items.filter((item) => String(item.session_id ?? "") === id);
}

function valueText(value: unknown, fallback = "") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function providerSparseText(data: DashboardData) {
  if (data.records.length === 0 && data.commands.length === 0 && data.events.length === 0) {
    return "No work has been recorded in this export yet.";
  }
  if (data.records.length > 0 && data.sessions.length === 0) {
    return "Work Records exist, but this capture path did not provide provider session metadata. Fixture-only or summary-only imports can still appear as records, commands, and summaries.";
  }
  return "Provider metadata is present but this section has no matching redacted events for the selected session.";
}

function evidenceTone(status: unknown): "ok" | "warn" | "danger" {
  const normalized = String(status ?? "").toLowerCase();
  if (normalized === "passed" || normalized === "succeeded" || normalized === "success") return "ok";
  if (normalized === "failed" || normalized === "error" || normalized === "failure") return "danger";
  return "warn";
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
