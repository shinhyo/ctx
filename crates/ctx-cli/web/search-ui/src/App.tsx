import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent } from "react"
import {
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
} from "@tanstack/react-table"
import {
  ArrowUpDown,
  Check,
  ChevronsUpDown,
  Copy,
  Database,
  Moon,
  RefreshCw,
  Search,
  Sun,
  TerminalSquare,
} from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { cn } from "@/lib/utils"

type SearchFilters = {
  q: string
  provider: string
  repo: string
  date_range: string
  since: string
  until: string
  event_type: string
  file: string
  limit: string
  include_subagents: boolean
}

type Citation = {
  item_id?: string | null
  item_type?: string | null
  label?: string | null
  time?: string | null
  provider?: string | null
  ctx_event_id?: string | null
  ctx_session_id?: string | null
}

type SearchResult = {
  item_id: string
  item_type?: string | null
  ctx_event_id?: string | null
  ctx_session_id?: string | null
  event_seq?: number | null
  title?: string | null
  snippet?: string | null
  rank?: number | null
  provider?: string | null
  provider_session_id?: string | null
  timestamp?: string | null
  cwd?: string | null
  source_path?: string | null
  source_exists?: boolean | null
  cursor?: string | null
  suggested_next_commands?: string[]
  why_matched?: string[]
  citations?: Citation[]
}

type SearchPacket = {
  query?: string
  generated_at?: string
  freshness?: {
    mode?: string
    status?: string
    source_count?: number
    error?: string | null
  }
  results?: SearchResult[]
  pagination?: {
    has_more?: boolean
  }
}

type FilterOption = {
  value: string
  label: string
}

type FilterOptions = {
  repos: string[]
  files: string[]
  event_types: FilterOption[]
}

const PROVIDERS = [
  "codex",
  "pi",
  "claude",
  "opencode",
  "antigravity",
  "gemini",
  "cursor",
  "copilot_cli",
  "factory_ai_droid",
]

const FALLBACK_EVENT_TYPES: FilterOption[] = [
  { value: "message", label: "Message" },
  { value: "tool_call", label: "Tool call" },
  { value: "tool_output", label: "Tool output" },
  { value: "command_started", label: "Command started" },
  { value: "command_output", label: "Command output" },
  { value: "command_finished", label: "Command finished" },
  { value: "file_touched", label: "File touched" },
  { value: "vcs_change", label: "VCS change" },
  { value: "artifact", label: "Artifact" },
  { value: "summary", label: "Summary" },
  { value: "notice", label: "Notice" },
]

const DATE_RANGE_PRESETS = [
  { value: "all", label: "Any time" },
  { value: "today", label: "Today" },
  { value: "yesterday", label: "Yesterday" },
  { value: "1d", label: "Last day" },
  { value: "7d", label: "Last 7 days" },
  { value: "30d", label: "Last 30 days" },
  { value: "90d", label: "Last 90 days" },
  { value: "365d", label: "Last year" },
  { value: "custom", label: "Custom range" },
]

function initialFilters(): SearchFilters {
  const params = new URLSearchParams(window.location.search)
  const primaryOnly = params.get("primary_only") === "true"
  const since = params.get("since") ?? ""
  const until = params.get("until") ?? ""
  return {
    q: params.get("q") ?? "",
    provider: params.get("provider") ?? "all",
    repo: params.get("repo") ?? "",
    date_range: initialDateRange(params.get("date_range"), since, until),
    since,
    until,
    event_type: params.get("event_type") ?? "",
    file: params.get("file") ?? "",
    limit: params.get("limit") ?? "20",
    include_subagents: primaryOnly ? false : params.get("include_subagents") !== "false",
  }
}

function initialTheme() {
  const params = new URLSearchParams(window.location.search)
  const fromUrl = params.get("theme")
  if (fromUrl === "dark" || fromUrl === "light") return fromUrl
  const stored = localStorage.getItem("ctx-search-theme")
  if (stored === "dark" || stored === "light") return stored
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

function initialDateRange(value: string | null, since: string, until: string) {
  if (value && DATE_RANGE_PRESETS.some((preset) => preset.value === value)) return value
  if (!since && !until) return "all"
  if (!until && DATE_RANGE_PRESETS.some((preset) => preset.value === since)) return since
  return "custom"
}

function display(value: unknown, fallback = "-") {
  if (value === null || value === undefined || value === "") return fallback
  return String(value)
}

function previewText(value?: string | null) {
  return display(value, "No preview")
    .replaceAll("\\n", "\n")
    .replaceAll('\\"', '"')
    .replaceAll("<subagent_notification>", "")
    .replaceAll("</subagent_notification>", "")
    .trim()
}

function shortId(value?: string | null) {
  if (!value) return "-"
  return value.slice(0, 8)
}

function percent(value?: number | null) {
  if (typeof value !== "number") return "-"
  return `${Math.round(value * 100)}%`
}

function formatTime(value?: string | null) {
  if (!value) return "-"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date)
}

function rangeBoundText(value: string, fallback: string) {
  if (!value) return fallback
  if (/^\d+d$/.test(value)) return "Preset start"
  return formatTime(value)
}

function DateBoundControl({
  id,
  label,
  value,
  fallback,
  isCustom,
  onChange,
}: {
  id: string
  label: string
  value: string
  fallback: string
  isCustom: boolean
  onChange: (value: string) => void
}) {
  if (isCustom) {
    return (
      <div className="relative">
        <span className="pointer-events-none absolute left-3 top-1/2 z-10 -translate-y-1/2 text-xs font-medium text-muted-foreground">
          {label}
        </span>
        <Input
          id={id}
          aria-label={label}
          type="datetime-local"
          step="60"
          className={cn("pl-14", !value && "[&::-webkit-datetime-edit]:text-transparent")}
          value={datetimeLocalValue(value)}
          onChange={(event) => onChange(event.target.value)}
        />
        {!value ? (
          <span className="pointer-events-none absolute left-14 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">
            {fallback}
          </span>
        ) : null}
      </div>
    )
  }

  return (
    <div
      id={id}
      className="flex h-9 items-center gap-3 rounded-md border bg-muted/40 px-3 text-sm text-muted-foreground"
    >
      <span className="text-xs font-medium">{label}</span>
      <span>{rangeBoundText(value, fallback)}</span>
    </div>
  )
}

function FreeTextCombobox({
  id,
  value,
  options,
  onChange,
  placeholder,
  emptyText,
  emptyFilterText,
}: {
  id: string
  value: string
  options: string[]
  onChange: (value: string) => void
  placeholder: string
  emptyText: string
  emptyFilterText: string
}) {
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(-1)
  const rootRef = useRef<HTMLDivElement>(null)
  const listId = useId()

  const visibleOptions = useMemo(() => {
    const query = value.trim().toLowerCase()
    const matches = query
      ? options.filter((option) => option.toLowerCase().includes(query))
      : options
    return matches.slice(0, 40)
  }, [options, value])

  useEffect(() => {
    setActiveIndex(visibleOptions.length ? 0 : -1)
  }, [visibleOptions.length, value])

  useEffect(() => {
    if (!open) return

    function handlePointerDown(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false)
    }

    document.addEventListener("pointerdown", handlePointerDown)
    return () => document.removeEventListener("pointerdown", handlePointerDown)
  }, [open])

  function choose(option: string) {
    onChange(option)
    setOpen(false)
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      setOpen(true)
      if (visibleOptions.length) {
        setActiveIndex((current) => (current < 0 ? 0 : (current + 1) % visibleOptions.length))
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      setOpen(true)
      if (visibleOptions.length) {
        setActiveIndex((current) =>
          current <= 0 ? visibleOptions.length - 1 : current - 1
        )
      }
    } else if (event.key === "Enter" && open && activeIndex >= 0 && visibleOptions[activeIndex]) {
      event.preventDefault()
      choose(visibleOptions[activeIndex])
    } else if (event.key === "Escape") {
      event.preventDefault()
      setOpen(false)
    }
  }

  return (
    <div ref={rootRef} className="relative">
      <Input
        id={id}
        value={value}
        onChange={(event) => {
          onChange(event.target.value)
          setOpen(true)
        }}
        onFocus={() => setOpen(true)}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        role="combobox"
        aria-expanded={open}
        aria-autocomplete="list"
        aria-controls={listId}
        aria-activedescendant={
          open && activeIndex >= 0 ? `${listId}-${activeIndex}` : undefined
        }
        className="pr-9"
      />
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        className="absolute right-0.5 top-0.5 size-7 text-muted-foreground"
        aria-label="Show suggestions"
        onClick={() => setOpen((current) => !current)}
      >
        <ChevronsUpDown className="size-3.5" />
      </Button>
      {open ? (
        <div
          id={listId}
          role="listbox"
          className="absolute left-0 right-0 top-[calc(100%+0.25rem)] z-50 max-h-72 overflow-auto rounded-lg border bg-popover p-1 text-popover-foreground shadow-md ring-1 ring-foreground/10"
        >
          {visibleOptions.length ? (
            visibleOptions.map((option, index) => {
              const selected = option === value
              const active = index === activeIndex
              return (
                <button
                  id={`${listId}-${index}`}
                  key={option}
                  type="button"
                  role="option"
                  aria-selected={selected}
                  className={cn(
                    "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm outline-none",
                    active ? "bg-accent text-accent-foreground" : "hover:bg-accent hover:text-accent-foreground"
                  )}
                  title={option}
                  onMouseEnter={() => setActiveIndex(index)}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => choose(option)}
                >
                  <span className="min-w-0 flex-1 truncate">{option}</span>
                  {selected ? <Check className="size-3.5 shrink-0" /> : null}
                </button>
              )
            })
          ) : (
            <div className="px-2 py-3 text-sm text-muted-foreground">
              {options.length ? emptyFilterText : emptyText}
            </div>
          )}
        </div>
      ) : null}
    </div>
  )
}

function compactPath(path?: string | null) {
  if (!path) return "-"
  if (path.includes("[REDACTED_PATH]")) return path
  const parts = path.split("/").filter(Boolean)
  return parts.length <= 3 ? path : `.../${parts.slice(-3).join("/")}`
}

function buildApiQuery(filters: SearchFilters) {
  const params = new URLSearchParams()
  for (const key of ["q", "repo", "since", "until", "event_type", "file", "limit"] as const) {
    const value = filters[key].trim()
    if (value) params.set(key, value)
  }
  if (filters.provider !== "all") params.set("provider", filters.provider)
  params.set("include_subagents", filters.include_subagents ? "true" : "false")
  return params
}

function updateUrl(filters: SearchFilters, theme: string) {
  const params = buildApiQuery(filters)
  if (filters.date_range && filters.date_range !== "all") params.set("date_range", filters.date_range)
  if (theme) params.set("theme", theme)
  window.history.replaceState(null, "", `/?${params.toString()}`)
}

function stripUrlToken() {
  const params = new URLSearchParams(window.location.search)
  if (!params.has("token")) return
  params.delete("token")
  const query = params.toString()
  window.history.replaceState(null, "", `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`)
}

function providerLabel(value?: string | null) {
  if (!value) return "unknown"
  const labels: Record<string, string> = {
    antigravity: "Antigravity",
    claude: "Claude",
    codex: "Codex",
    copilot_cli: "Copilot CLI",
    cursor: "Cursor",
    factory_ai_droid: "Factory AI Droid",
    gemini: "Gemini",
    opencode: "OpenCode",
    pi: "Pi",
  }
  return labels[value] ?? value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase())
}

function pad2(value: number) {
  return String(value).padStart(2, "0")
}

function datetimeLocalValue(value: string) {
  if (!value || /^\d+d$/.test(value)) return ""
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""
  return [
    date.getFullYear(),
    pad2(date.getMonth() + 1),
    pad2(date.getDate()),
  ].join("-") + `T${pad2(date.getHours())}:${pad2(date.getMinutes())}`
}

function datetimeRangeValue(value: string) {
  if (!value) return ""
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? "" : date.toISOString()
}

function startOfLocalDay(date: Date) {
  const next = new Date(date)
  next.setHours(0, 0, 0, 0)
  return next
}

function endOfLocalDay(date: Date) {
  const next = new Date(date)
  next.setHours(23, 59, 59, 999)
  return next
}

function daysAgoStart(days: number) {
  const next = startOfLocalDay(new Date())
  next.setDate(next.getDate() - days)
  return next
}

function tableColumnClass(columnId: string) {
  switch (columnId) {
    case "rank":
      return "w-20"
    case "provider":
      return "w-44"
    default:
      return ""
  }
}

function ResultDetail({
  result,
  packet,
  onCopy,
  copiedValue,
  copyError,
}: {
  result?: SearchResult
  packet?: SearchPacket
  onCopy: (value: string) => void
  copiedValue?: string
  copyError?: string
}) {
  if (!result) {
    return (
      <Card className="h-full">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <TerminalSquare className="size-4" />
            Result detail
          </CardTitle>
          <CardDescription>Select a row to inspect it.</CardDescription>
        </CardHeader>
      </Card>
    )
  }

  const commands = result.suggested_next_commands ?? []
  const primaryCommand = commands[0]
  const extraCommands = commands.slice(1)
  const citations = result.citations ?? []
  const copyLabel = (value: string) => {
    if (copiedValue === value) return "Copied"
    if (copyError === value) return "Failed"
    return "Copy"
  }

  return (
    <Card className="h-full">
      <CardHeader className="space-y-3">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
          <span>{display(result.item_type, "result")}</span>
          <span>{providerLabel(result.provider)}</span>
          {result.source_exists === false ? (
            <span className="text-amber-700 dark:text-amber-300">source missing</span>
          ) : null}
        </div>
        <CardTitle className="text-lg leading-snug">{display(result.title, "Untitled result")}</CardTitle>
        <CardDescription>
          rank {percent(result.rank)} · {formatTime(result.timestamp)}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="grid gap-3 text-sm">
          <div className="grid gap-1 sm:grid-cols-[88px_minmax(0,1fr)] sm:gap-3">
            <span className="text-muted-foreground">Event</span>
            <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2">
              <code className="block overflow-x-auto rounded-md bg-muted px-2 py-1 text-xs">
                {display(result.ctx_event_id)}
              </code>
              {result.ctx_event_id ? (
                <Button variant="outline" size="sm" onClick={() => onCopy(result.ctx_event_id ?? "")}>
                  {copyLabel(result.ctx_event_id)}
                </Button>
              ) : null}
            </div>
          </div>
          <div className="grid gap-1 sm:grid-cols-[88px_minmax(0,1fr)] sm:gap-3">
            <span className="text-muted-foreground">Session</span>
            <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2">
              <code className="block overflow-x-auto rounded-md bg-muted px-2 py-1 text-xs">
                {display(result.ctx_session_id)}
              </code>
              {result.ctx_session_id ? (
                <Button variant="outline" size="sm" onClick={() => onCopy(result.ctx_session_id ?? "")}>
                  {copyLabel(result.ctx_session_id)}
                </Button>
              ) : null}
            </div>
          </div>
          <div className="grid gap-1 sm:grid-cols-[88px_minmax(0,1fr)] sm:gap-3">
            <span className="text-muted-foreground">Source</span>
            <span className="break-words">{compactPath(result.source_path)}</span>
          </div>
        </div>

        <Separator />

        <div className="space-y-2">
          <div className="text-sm font-medium">Preview</div>
          <pre className="max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-lg border bg-muted/50 p-3 text-sm leading-6">
            {previewText(result.snippet)}
          </pre>
        </div>

        <div className="space-y-2">
          <div className="text-sm font-medium">Command</div>
          {primaryCommand ? (
            <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 rounded-lg border bg-card p-2">
              <code className="break-all text-xs">{primaryCommand}</code>
              <Button variant="outline" size="sm" onClick={() => onCopy(primaryCommand)}>
                <Copy className="size-3.5" />
                {copyLabel(primaryCommand)}
              </Button>
            </div>
          ) : (
            <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
              No command available.
            </div>
          )}
          {extraCommands.length ? (
            <details className="rounded-lg border bg-card p-3 text-sm">
              <summary className="cursor-pointer text-muted-foreground">
                More commands ({extraCommands.length})
              </summary>
              <div className="mt-3 grid gap-2">
                {extraCommands.map((command) => (
                <div
                  key={command}
                  className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 rounded-lg border bg-card p-2"
                >
                  <code className="break-all text-xs">{command}</code>
                  <Button variant="outline" size="sm" onClick={() => onCopy(command)}>
                    <Copy className="size-3.5" />
                    {copyLabel(command)}
                  </Button>
                </div>
                ))}
              </div>
            </details>
          ) : null}
        </div>

        {citations.length ? (
          <details className="rounded-lg border bg-card p-3 text-sm">
            <summary className="cursor-pointer text-muted-foreground">
              Citations ({citations.length})
            </summary>
            <div className="mt-3 grid gap-2">
              {citations.slice(0, 6).map((citation, index) => (
                <div key={`${citation.item_id}-${index}`} className="rounded-lg border p-3">
                  <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span>{display(citation.item_type, "citation")}</span>
                    <span>{formatTime(citation.time)}</span>
                  </div>
                  <code className="mt-2 block break-all text-xs">{display(citation.item_id)}</code>
                </div>
              ))}
            </div>
          </details>
        ) : null}

        {packet?.pagination?.has_more ? (
          <div className="rounded-lg border border-teal-200 bg-teal-50 p-3 text-sm text-teal-800 dark:border-teal-900 dark:bg-teal-950 dark:text-teal-200">
            More results are available. Increase the limit or narrow filters.
          </div>
        ) : null}
      </CardContent>
    </Card>
  )
}

export default function App() {
  const [filters, setFilters] = useState<SearchFilters>(() => initialFilters())
  const [theme, setTheme] = useState(() => initialTheme())
  const [packet, setPacket] = useState<SearchPacket>()
  const [results, setResults] = useState<SearchResult[]>([])
  const [selectedId, setSelectedId] = useState<string>()
  const [sorting, setSorting] = useState<SortingState>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string>()
  const [filterOptions, setFilterOptions] = useState<FilterOptions>({
    repos: [],
    files: [],
    event_types: FALLBACK_EVENT_TYPES,
  })
  const [copiedValue, setCopiedValue] = useState<string>()
  const [copyError, setCopyError] = useState<string>()
  const detailRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    stripUrlToken()
  }, [])

  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark")
    document.documentElement.style.colorScheme = theme
    localStorage.setItem("ctx-search-theme", theme)
  }, [theme])

  const selected = results.find((result) => result.item_id === selectedId) ?? results[0]

  const columns = useMemo<ColumnDef<SearchResult>[]>(
    () => [
      {
        accessorKey: "rank",
        header: ({ column }) => (
          <Button
            variant="ghost"
            size="sm"
            className="px-0"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            Rank
            <ArrowUpDown className="size-3.5" />
          </Button>
        ),
        cell: ({ row }) => (
          <span className="text-sm tabular-nums text-muted-foreground">
            {percent(row.original.rank)}
          </span>
        ),
      },
      {
        accessorKey: "title",
        header: "Result",
        cell: ({ row }) => (
          <div className="min-w-0 space-y-1">
            <div className="min-w-0 space-y-1">
              <span className="truncate font-medium leading-snug">{display(row.original.title, "Untitled result")}</span>
              <span className="block text-xs text-muted-foreground">{display(row.original.item_type, "result")}</span>
            </div>
            <div className="truncate text-sm leading-6 text-muted-foreground">
              {previewText(row.original.snippet)}
            </div>
          </div>
        ),
      },
      {
        accessorKey: "provider",
        header: "Provider",
        cell: ({ row }) => (
          <div className="space-y-1 text-sm">
            <div>{providerLabel(row.original.provider)}</div>
            <div className="text-xs text-muted-foreground">event {shortId(row.original.ctx_event_id)}</div>
            <div className="text-xs text-muted-foreground">{formatTime(row.original.timestamp)}</div>
          </div>
        ),
      },
    ],
    []
  )

  const table = useReactTable({
    data: results,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  async function runSearch(nextFilters = filters) {
    setLoading(true)
    setError(undefined)
    setResults([])
    setSelectedId(undefined)
    setPacket(undefined)
    try {
      const params = buildApiQuery(nextFilters)
      const response = await fetch(`/api/search?${params.toString()}`, {
        headers: { Accept: "application/json" },
      })
      if (!response.ok) throw new Error(`Search failed: ${response.status}`)
      const nextPacket = (await response.json()) as SearchPacket
      const nextResults = nextPacket.results ?? []
      setPacket(nextPacket)
      setResults(nextResults)
      setSelectedId(nextResults[0]?.item_id)
      updateUrl(nextFilters, theme)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Search failed")
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (filters.q.trim()) void runSearch(filters)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    async function loadFilterOptions() {
      try {
        const response = await fetch("/api/filter-options", {
          headers: { Accept: "application/json" },
        })
        if (!response.ok) return
        const options = (await response.json()) as Partial<FilterOptions>
        setFilterOptions({
          repos: Array.isArray(options.repos) ? options.repos : [],
          files: Array.isArray(options.files) ? options.files : [],
          event_types: Array.isArray(options.event_types) && options.event_types.length ? options.event_types : FALLBACK_EVENT_TYPES,
        })
      } catch {
        // Suggestions are optional; free-text filters still work.
      }
    }

    void loadFilterOptions()
  }, [])

  function setFilter<K extends keyof SearchFilters>(key: K, value: SearchFilters[K]) {
    setFilters((current) => ({ ...current, [key]: value }))
  }

  function setDateRange(value: string) {
    setFilters((current) => {
      const today = new Date()
      const yesterday = new Date(today)
      yesterday.setDate(yesterday.getDate() - 1)
      switch (value) {
        case "all":
          return { ...current, date_range: value, since: "", until: "" }
        case "today":
          return {
            ...current,
            date_range: value,
            since: startOfLocalDay(today).toISOString(),
            until: endOfLocalDay(today).toISOString(),
          }
        case "yesterday":
          return {
            ...current,
            date_range: value,
            since: startOfLocalDay(yesterday).toISOString(),
            until: endOfLocalDay(yesterday).toISOString(),
          }
        case "1d":
        case "7d":
        case "30d":
        case "90d":
        case "365d":
          return { ...current, date_range: value, since: value, until: "" }
        case "custom":
          return {
            ...current,
            date_range: value,
            since: /^\d+d$/.test(current.since) ? daysAgoStart(7).toISOString() : current.since,
          }
        default:
          return current
      }
    })
  }

  function setRangeBound(key: "since" | "until", value: string) {
    setFilters((current) => ({
      ...current,
      date_range: "custom",
      [key]: datetimeRangeValue(value),
    }))
  }

  function selectResult(id: string, revealDetail = false) {
    setSelectedId(id)
    if (revealDetail) {
      window.setTimeout(() => {
        detailRef.current?.scrollIntoView({ behavior: "smooth", block: "start" })
      }, 0)
    }
  }

  async function copy(value: string) {
    try {
      await navigator.clipboard.writeText(value)
      setCopiedValue(value)
      setCopyError(undefined)
      window.setTimeout(() => setCopiedValue(undefined), 1400)
    } catch {
      setCopyError(value)
      window.setTimeout(() => setCopyError(undefined), 1800)
    }
  }

  const detail = (
    <ResultDetail
      result={selected}
      packet={packet}
      onCopy={copy}
      copiedValue={copiedValue}
      copyError={copyError}
    />
  )

  return (
    <div className="min-h-dvh bg-muted/30 text-foreground">
      <header className="border-b bg-background">
        <div className="mx-auto flex max-w-[1500px] items-center justify-between gap-4 px-4 py-3 sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <div className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <Database className="size-4" />
            </div>
            <div className="min-w-0">
              <h1 className="text-lg font-semibold">ctx search</h1>
              <div className="text-sm text-muted-foreground">Agent history</div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {copiedValue ? <span className="hidden text-sm text-muted-foreground sm:inline">Copied</span> : null}
            <Button
              variant="outline"
              size="icon"
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              aria-label="Toggle theme"
            >
              {theme === "dark" ? <Sun className="size-4" /> : <Moon className="size-4" />}
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto grid max-w-[1500px] gap-4 px-4 py-4 sm:px-6 lg:grid-cols-[minmax(0,1fr)_430px]">
        <section className="min-w-0 space-y-4">
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Search</CardTitle>
            </CardHeader>
            <CardContent>
              <form
                className="grid gap-3"
                onSubmit={(event) => {
                  event.preventDefault()
                  void runSearch()
                }}
              >
                <div className="grid gap-3 lg:grid-cols-[minmax(280px,1fr)_minmax(96px,140px)]">
                  <div className="grid gap-1.5">
                    <Label htmlFor="ctx-search-query">Query</Label>
                    <div className="relative">
                      <Search className="pointer-events-none absolute left-3 top-2.5 size-4 text-muted-foreground" />
                      <Input
                        id="ctx-search-query"
                        className="pl-9"
                        value={filters.q}
                        onChange={(event) => setFilter("q", event.target.value)}
                        placeholder="keyword, error, file name"
                      />
                    </div>
                  </div>
                  <div className="grid gap-1.5">
                    <Label htmlFor="ctx-search-limit">Limit</Label>
                    <Input
                      id="ctx-search-limit"
                      value={filters.limit}
                      onChange={(event) => setFilter("limit", event.target.value)}
                      inputMode="numeric"
                    />
                  </div>
                </div>

                <div className="grid gap-2">
                  <Label>Date range</Label>
                  <div
                    className={cn(
                      "grid gap-2",
                      filters.date_range === "custom"
                        ? "md:grid-cols-[minmax(140px,0.7fr)_minmax(210px,1fr)_minmax(210px,1fr)]"
                        : "md:grid-cols-[minmax(140px,220px)]"
                    )}
                  >
                    <Select value={filters.date_range} onValueChange={setDateRange}>
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {DATE_RANGE_PRESETS.map((preset) => (
                          <SelectItem key={preset.value} value={preset.value}>
                            {preset.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {filters.date_range === "custom" ? (
                      <>
                        <DateBoundControl
                          id="ctx-search-from"
                          label="From"
                          value={filters.since}
                          fallback="No start"
                          isCustom
                          onChange={(value) => setRangeBound("since", value)}
                        />
                        <DateBoundControl
                          id="ctx-search-to"
                          label="To"
                          value={filters.until}
                          fallback="No end"
                          isCustom
                          onChange={(value) => setRangeBound("until", value)}
                        />
                      </>
                    ) : null}
                  </div>
                </div>

                <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-[minmax(140px,0.7fr)_minmax(140px,0.7fr)_minmax(180px,1fr)_minmax(180px,1fr)]">
                  <div className="grid gap-1.5">
                    <Label>Provider</Label>
                    <Select value={filters.provider} onValueChange={(value) => setFilter("provider", value)}>
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All providers</SelectItem>
                        {PROVIDERS.map((provider) => (
                          <SelectItem key={provider} value={provider}>
                            {providerLabel(provider)}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="grid gap-1.5">
                    <Label>Event type</Label>
                    <Select
                      value={filters.event_type || "all"}
                      onValueChange={(value) => setFilter("event_type", value === "all" ? "" : value)}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All event types</SelectItem>
                        {filterOptions.event_types.map((eventType) => (
                          <SelectItem key={eventType.value} value={eventType.value}>
                            {eventType.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="grid gap-1.5">
                    <Label htmlFor="ctx-search-repo">Repo</Label>
                    <Input
                      id="ctx-search-repo"
                      list="ctx-search-repo-options"
                      value={filters.repo}
                      onChange={(event) => setFilter("repo", event.target.value)}
                      placeholder="Type or choose"
                    />
                  </div>
                  <div className="grid gap-1.5">
                    <Label htmlFor="ctx-search-file">Touched file</Label>
                    <FreeTextCombobox
                      id="ctx-search-file"
                      value={filters.file}
                      placeholder="Type or choose"
                      options={filterOptions.files}
                      emptyText="No indexed touched files"
                      emptyFilterText="No matching touched files"
                      onChange={(value) => setFilter("file", value)}
                    />
                  </div>
                </div>
                <datalist id="ctx-search-repo-options">
                  {filterOptions.repos.map((repo) => (
                    <option key={repo} value={repo} />
                  ))}
                </datalist>

                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <Label className="flex items-center gap-2">
                    <Switch checked={filters.include_subagents} onCheckedChange={(value) => setFilter("include_subagents", value)} />
                    Include subagent sessions
                  </Label>
                  <Button type="submit" disabled={loading} className="sm:min-w-28">
                    {loading ? <RefreshCw className="size-4 animate-spin" /> : <Search className="size-4" />}
                    Search
                  </Button>
                </div>
              </form>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <CardTitle className="text-base">Results</CardTitle>
                  <CardDescription>
                    {loading
                      ? "Searching..."
                      : packet?.generated_at
                        ? `${results.length} results · Generated ${formatTime(packet.generated_at)}`
                        : "No search run"}
                  </CardDescription>
                </div>
                {error ? <span className="text-sm text-destructive">{error}</span> : null}
              </div>
            </CardHeader>
            <CardContent className="p-0">
              <div className="grid divide-y md:hidden">
                {results.length ? (
                  results.map((result) => (
                    <button
                      key={result.item_id}
                      type="button"
                      className={cn(
                        "grid gap-1 px-4 py-4 text-left transition-colors",
                        result.item_id === selected?.item_id ? "bg-muted" : "hover:bg-muted/60"
                      )}
                      onClick={() => selectResult(result.item_id, true)}
                    >
                      <div className="flex items-center justify-between gap-3 text-sm text-muted-foreground">
                        <span>{percent(result.rank)}</span>
                        <span>{providerLabel(result.provider)}</span>
                      </div>
                      <div className="font-medium leading-snug">{display(result.title, "Untitled result")}</div>
                      <div className="text-xs text-muted-foreground">{display(result.item_type, "result")}</div>
                      <div className="line-clamp-2 text-sm leading-6 text-muted-foreground">
                        {previewText(result.snippet)}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        event {shortId(result.ctx_event_id)} · {formatTime(result.timestamp)}
                      </div>
                    </button>
                  ))
                ) : (
                  <div className="px-4 py-16 text-center text-sm text-muted-foreground">
                    {loading ? "Searching..." : "No results"}
                  </div>
                )}
              </div>
              <div className="hidden overflow-auto md:block">
                <Table className="min-w-[720px] table-fixed">
                  <TableHeader>
                    {table.getHeaderGroups().map((headerGroup) => (
                      <TableRow key={headerGroup.id}>
                        {headerGroup.headers.map((header) => (
                          <TableHead
                            key={header.id}
                            className={cn("whitespace-nowrap", tableColumnClass(header.column.id))}
                          >
                            {header.isPlaceholder ? null : flexRender(header.column.columnDef.header, header.getContext())}
                          </TableHead>
                        ))}
                      </TableRow>
                    ))}
                  </TableHeader>
                  <TableBody>
                    {table.getRowModel().rows.length ? (
                      table.getRowModel().rows.map((row) => (
                        <TableRow
                          key={row.original.item_id}
                          tabIndex={0}
                          data-state={row.original.item_id === selected?.item_id ? "selected" : undefined}
                          className="cursor-pointer align-top data-[state=selected]:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                          onClick={() => selectResult(row.original.item_id)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter" || event.key === " ") selectResult(row.original.item_id)
                          }}
                        >
                          {row.getVisibleCells().map((cell) => (
                            <TableCell key={cell.id} className={tableColumnClass(cell.column.id)}>
                              {flexRender(cell.column.columnDef.cell, cell.getContext())}
                            </TableCell>
                          ))}
                        </TableRow>
                      ))
                    ) : (
                      <TableRow>
                        <TableCell colSpan={columns.length} className="h-40 text-center text-muted-foreground">
                          {loading ? "Searching..." : "No results"}
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>

          <div ref={detailRef} className="lg:hidden">
            {detail}
          </div>
        </section>

        <aside className="hidden min-w-0 lg:block">
          <div className="sticky top-4">{detail}</div>
        </aside>
      </main>
    </div>
  )
}
