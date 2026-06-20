import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import type { APIRequestContext, Locator, Page } from "@playwright/test";
import { test, expect } from "./fixtures";
import { seedDummyWorkspace } from "./utils/seedDummyWorkspace";
import {
  buildVisualName,
  captureVisual,
  visualViewportLabel,
  waitForVisualSettled,
  type VisualTheme,
  type VisualViewportName,
} from "./utils/visual";
import {
  activeSessionComposer,
  openWorkbenchVisualPage,
} from "./utils/visualWorkbench";

type TemplateLabel = "Classic" | "Kanban" | "Multipane" | "Review";

const THEME: VisualTheme = "dark";
const TEMPLATE_LABELS = ["Classic", "Kanban", "Multipane", "Review"] as const satisfies TemplateLabel[];
const TEMPLATE_VIEWPORTS = ["desktop-wide", "laptop", "narrow"] as const satisfies VisualViewportName[];
const TEMPLATE_CLASS_BY_LABEL: Record<TemplateLabel, string> = {
  Classic: "classic",
  Kanban: "kanban",
  Multipane: "multipane",
  Review: "review",
};

const VISUAL_PLUGIN_ID = "visual.review-tools";
const HOT_RELOAD_PLUGIN_ID = "visual.hot-reload-tools";

function e2ePluginRoot() {
  const dataDir = process.env.CTX_E2E_DATA_DIR;
  if (!dataDir) {
    throw new Error("CTX_E2E_DATA_DIR is required for visual plugin seeding");
  }
  return path.join(dataDir, "plugins");
}

function visualPluginDir() {
  return path.join(e2ePluginRoot(), "visual-review-tools");
}

function hotReloadPluginDir() {
  return path.join(e2ePluginRoot(), "visual-hot-reload-tools");
}

function pluginTemplateId(pluginId: string, contributionId: string) {
  return `plugin:${encodeURIComponent(pluginId)}/${encodeURIComponent(contributionId)}`;
}

async function reloadPluginsForVisual(request: APIRequestContext) {
  const reload = await request.post("/api/plugins/reload");
  expect(reload.ok(), await reload.text()).toBeTruthy();
  return reload.json() as Promise<{ plugins?: Array<{ id?: string; status?: string }> }>;
}

async function seedVisualWorkbenchPlugin(request: APIRequestContext) {
  const pluginDir = visualPluginDir();
  await mkdir(pluginDir, { recursive: true });
  await writeFile(
    path.join(pluginDir, "ctx-plugin.json"),
    JSON.stringify(
      {
        schema_version: 1,
        id: VISUAL_PLUGIN_ID,
        name: "Visual Review Tools With Very Long Labels",
        version: "0.1.0",
        entrypoints: [
          {
            id: "main",
            command: "sh",
            args: ["-c", "cat >/dev/null; printf '{\"message\":\"visual command fixture\"}'"],
          },
        ],
        contributes: {
          commands: [
            {
              id: "review-evidence",
              title: "Review Evidence",
              description: "Open the visual review evidence workflow.",
              category: "Review",
              entrypoint: "main",
            },
          ],
          ui_surfaces: [
            {
              id: `${VISUAL_PLUGIN_ID}.review_panel`,
              name: "Review telemetry and contribution diagnostics panel",
              surface: "panel",
              contexts: ["workbench", "review"],
            },
          ],
          templates: [
            {
              id: `${VISUAL_PLUGIN_ID}.dense_review_template`,
              name: "Dense review evidence template with long title",
              title: "Dense Review Evidence",
              template: "review",
              contexts: ["workbench"],
              data_sources: ["agent_work", "plugin_registry"],
            },
          ],
          toolbar_actions: [
            {
              id: `${VISUAL_PLUGIN_ID}.focus_work`,
              name: "Focus current work item",
              title: "Focus Work",
              action: "work.focus",
              icon: "crosshair",
              contexts: ["workbench"],
            },
          ],
          artifact_renderers: [
            {
              id: `${VISUAL_PLUGIN_ID}.long_text_artifact`,
              name: "Long text artifact renderer",
              artifact_types: ["text/plain", "application/vnd.ctx.agent-work+json"],
              renderer: "host.text-artifact",
              contexts: ["workbench"],
            },
          ],
          card_renderers: [
            {
              id: `${VISUAL_PLUGIN_ID}.work_summary_card`,
              name: "Work summary card renderer",
              card: "work.summary",
              renderer: "host.work-summary-card",
              contexts: ["workbench"],
            },
          ],
          detail_sections: [
            {
              id: `${VISUAL_PLUGIN_ID}.work_summary_section`,
              name: "Work summary detail section",
              section: "work.summary",
              renderer: "host.work-summary-section",
              contexts: ["workbench"],
            },
          ],
          review_sections: [
            {
              id: `${VISUAL_PLUGIN_ID}.unsupported_custom_review_section`,
              name: "Unsupported custom review section with deliberately long source label",
              section: "review.custom-untrusted",
              renderer: "plugin.visual-review-renderer",
              contexts: ["workbench", "review"],
            },
          ],
        },
      },
      null,
      2,
    ),
    "utf8",
  );

  const inventory = await reloadPluginsForVisual(request);
  expect(inventory.plugins?.some((plugin: { id?: string; status?: string }) => (
    plugin.id === VISUAL_PLUGIN_ID && plugin.status === "loaded"
  ))).toBeTruthy();
}

async function writeHotReloadPlugin(label: string) {
  const pluginDir = hotReloadPluginDir();
  await mkdir(pluginDir, { recursive: true });
  await writeFile(
    path.join(pluginDir, "ctx-plugin.json"),
    JSON.stringify(
      {
        schema_version: 1,
        id: HOT_RELOAD_PLUGIN_ID,
        name: label,
        version: "0.1.0",
        contributes: {
          ui_surfaces: [
            {
              id: `${HOT_RELOAD_PLUGIN_ID}.panel`,
              name: `${label} contribution panel`,
              surface: "panel",
              contexts: ["workbench"],
            },
          ],
        },
      },
      null,
      2,
    ),
    "utf8",
  );
}

async function removePluginDir(pluginDir: string) {
  await rm(pluginDir, { recursive: true, force: true });
}

async function selectTemplate(page: Page, label: TemplateLabel) {
  await page.getByRole("radio", { name: label, exact: true }).click();
  await expect(page.getByRole("radio", { name: label, exact: true })).toHaveAttribute("aria-checked", "true");
  await expect(page.locator(`.wb-main-template-${TEMPLATE_CLASS_BY_LABEL[label]}`)).toBeVisible({
    timeout: 20_000,
  });
}

function visibleFixtureTasks(page: Page) {
  return page.getByRole("listitem").filter({ hasText: /fixture task/i });
}

async function openFirstVisibleTaskSession(page: Page) {
  const rows = visibleFixtureTasks(page);
  if (!(await rows.first().isVisible().catch(() => false))) {
    const openTaskList = page.getByRole("button", { name: "Open task list" });
    if (await openTaskList.isVisible().catch(() => false)) {
      await openTaskList.click();
    }
  }
  await expect(rows.first()).toBeVisible({ timeout: 20_000 });
  await rows.first().click();
  await expect(activeSessionComposer(page)).toBeVisible({ timeout: 20_000 });
}

async function openSeededTemplateState(
  page: Page,
  opts: { workspaceId: string; viewport: VisualViewportName; template: TemplateLabel },
) {
  await openWorkbenchVisualPage(page, opts.workspaceId, { theme: THEME, viewport: opts.viewport });
  await openFirstVisibleTaskSession(page);
  await selectTemplate(page, opts.template);
  await waitForVisualSettled(page, {
    ready: page.locator(`.wb-main-template-${TEMPLATE_CLASS_BY_LABEL[opts.template]}`),
  });
}

async function installProviderCommandHeadFixture(page: Page, sessionId: string) {
  await page.route(`**/api/sessions/${sessionId}/head**`, async (route) => {
    const response = await route.fetch();
    const json = await response.json();
    const events = Array.isArray(json.events) ? [...json.events] : [];
    const hasFixture = events.some((event) => event?.id === "visual-provider-command-init");
    const seqs = events
      .map((event) => Number(event?.seq))
      .filter((seq) => Number.isFinite(seq));
    const nextSeq = Math.max(Number(json.last_event_seq ?? 0), ...seqs, 0) + 1;
    const patched = hasFixture
      ? json
      : {
          ...json,
          last_event_seq: Math.max(Number(json.last_event_seq ?? 0), nextSeq),
          events: [
            ...events,
            {
              seq: nextSeq,
              id: "visual-provider-command-init",
              session_id: sessionId,
              run_id: null,
              turn_id: null,
              event_type: "init",
              payload_json: {
                commands: [
                  {
                    name: "provider-review",
                    description: "Inspect the provider command surface.",
                    argument_hint: "<scope>",
                  },
                ],
                slash_commands: ["provider-review"],
              },
              transient: false,
              created_at: "2026-01-01T00:00:00.000Z",
            },
          ],
        };
    await route.fulfill({ response, json: patched });
  });
}

async function seedPluginTemplateSessionSelection(
  page: Page,
  opts: { workspaceId: string; templateId: string },
) {
  return page.evaluate(({ workspaceId, templateId }) => {
    const windowId = sessionStorage.getItem("contextUiWindowId.v1");
    if (!windowId) {
      throw new Error("Workbench window id was not initialized before seeding a template");
    }
    const expectedSuffix = `.${encodeURIComponent(workspaceId)}.${encodeURIComponent(windowId)}`;
    const keys = Object.keys(sessionStorage);
    let key = keys.find(
      (candidate) => candidate.startsWith("wb.template.session.v1.") && candidate.endsWith(expectedSuffix),
    );
    if (!key) {
      const windowKey = keys.find(
        (candidate) => candidate.startsWith("wb.window.session.v1.") && candidate.endsWith(expectedSuffix),
      );
      if (!windowKey) {
        throw new Error(`Workbench session key was not initialized for ${workspaceId}/${windowId}`);
      }
      key = `wb.template.session.v1.${windowKey.slice("wb.window.session.v1.".length)}`;
    }
    if (!key) {
      throw new Error(`Workbench template session key was not initialized for ${workspaceId}/${windowId}`);
    }
    sessionStorage.setItem(
      key,
      JSON.stringify({
        v: 1,
        template: {
          id: templateId,
          version: 1,
          layout: {},
        },
      }),
    );
    return key;
  }, opts);
}

function contributionRow(panel: Locator, title: string): Locator {
  return panel.locator(".wb-contribution-projection-row", { hasText: title }).first();
}

function autocompleteRow(autocomplete: Locator, label: string): Locator {
  return autocomplete.locator(".composer-ac-item", { hasText: label }).first();
}

async function expectNoHorizontalOverflow(locator: Locator) {
  await expect(locator).toBeVisible({ timeout: 20_000 });
  const overflow = await locator.evaluate((element) => ({
    clientWidth: element.clientWidth,
    scrollWidth: element.scrollWidth,
  }));
  expect(overflow.scrollWidth).toBeLessThanOrEqual(overflow.clientWidth + 2);
}

test.describe.serial("visual: workbench templates", () => {
  test.describe.configure({ timeout: 180_000 });
  let templateWorkspaceId = "";
  let denseWorkspaceId = "";
  let commandWorkspaceId = "";
  let commandSessionId = "";

  test.beforeAll(async ({ request }) => {
    test.setTimeout(180_000);
    const templateSeed = await seedDummyWorkspace(request, {
      tasks: 8,
      sessionsPerTask: 1,
      turnsPerSession: 3,
      throttleMs: 0,
      messagePrefix: "template visual fixture",
      messageBodyLines: { min: 2, max: 5 },
      includeToolSummaries: true,
      toolSummariesPerTurn: 2,
      seedTranscriptDirect: true,
      directSeedMaterializedTailTurns: 3,
    });
    templateWorkspaceId = templateSeed.workspaceId;

    const denseSeed = await seedDummyWorkspace(request, {
      tasks: 24,
      sessionsPerTask: 0,
      turnsPerSession: 0,
      throttleMs: 0,
      messagePrefix: "dense visual fixture",
      seedTranscriptDirect: true,
    });
    denseWorkspaceId = denseSeed.workspaceId;

    const commandSeed = await seedDummyWorkspace(request, {
      tasks: 1,
      sessionsPerTask: 1,
      turnsPerSession: 0,
      throttleMs: 0,
      seedTranscriptDirect: true,
      sessionSource: {
        providerId: "codex",
        modelId: "gpt-5",
        executionEnvironment: "host",
      },
    });
    commandWorkspaceId = commandSeed.workspaceId;
    commandSessionId = commandSeed.sessionIdsByTask[commandSeed.taskIds[0] ?? ""]?.[0] ?? "";
    expect(commandSessionId).toBeTruthy();

    await seedVisualWorkbenchPlugin(request);
  });

  for (const template of TEMPLATE_LABELS) {
    for (const viewport of TEMPLATE_VIEWPORTS) {
      test(`${template} template ${viewport}`, async ({ page }) => {
        await openSeededTemplateState(page, {
          workspaceId: templateWorkspaceId,
          viewport,
          template,
        });
        await captureVisual(
          page,
          buildVisualName([
            "workbench-template",
            TEMPLATE_CLASS_BY_LABEL[template],
            THEME,
            visualViewportLabel(viewport),
          ]),
        );
      });
    }
  }

  test("classic high-density task list desktop-wide", async ({ page }) => {
    await openWorkbenchVisualPage(page, denseWorkspaceId, { theme: THEME, viewport: "desktop-wide" });
    await expect
      .poll(async () => visibleFixtureTasks(page).count(), { timeout: 20_000 })
      .toBeGreaterThanOrEqual(16);
    await selectTemplate(page, "Classic");
    await captureVisual(
      page,
      buildVisualName(["workbench-template", "classic", "dense-task-list", THEME, visualViewportLabel("desktop-wide")]),
    );
  });

  test("multipane focus and resize sequence desktop-wide", async ({ page }) => {
    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "desktop-wide",
      template: "Multipane",
    });

    await captureVisual(
      page,
      buildVisualName(["workbench-template", "multipane", "sequence-initial", THEME, "desktop-wide"]),
    );

    await page.getByRole("button", { name: "Split right" }).click();
    const panes = page.locator(".wb-split-pane");
    await expect(panes).toHaveCount(2, { timeout: 20_000 });
    await expect(page.getByRole("separator", { name: "Resize panes" })).toHaveCount(1, { timeout: 20_000 });
    await captureVisual(
      page,
      buildVisualName(["workbench-template", "multipane", "split-right-empty-focused", THEME, "desktop-wide"]),
    );

    await panes.first().click();
    await expect(panes.first()).toHaveClass(/wb-split-pane-active/, { timeout: 20_000 });
    await captureVisual(
      page,
      buildVisualName(["workbench-template", "multipane", "focus-primary-pane", THEME, "desktop-wide"]),
    );

    const resizeHandle = page.getByRole("separator", { name: "Resize panes" });
    await resizeHandle.focus();
    await resizeHandle.press("ArrowRight");
    await expect(resizeHandle).toHaveAttribute("aria-valuenow", "55", { timeout: 20_000 });
    await captureVisual(
      page,
      buildVisualName(["workbench-template", "multipane", "resized-right", THEME, "desktop-wide"]),
    );
  });

  test("plugin contribution panel desktop-tight", async ({ page }) => {
    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "desktop-tight",
      template: "Classic",
    });

    const panel = page.getByRole("region", { name: "Workbench contributions" });
    await expect(panel).toContainText("Host-owned projection only", { timeout: 20_000 });
    const supportedPanelRow = contributionRow(panel, "Review telemetry and contribution diagnostics panel");
    await expect(supportedPanelRow.locator(".wb-contribution-projection-source")).toHaveText(
      "Visual Review Tools With Very Long Labels 0.1.0",
    );
    await expect(supportedPanelRow.locator(".wb-contribution-projection-state")).toHaveText("Projected");
    const unsupportedRendererRow = contributionRow(
      panel,
      "Unsupported custom review section with deliberately long source label",
    );
    await expect(unsupportedRendererRow.locator(".wb-contribution-projection-source")).toHaveText(
      "Visual Review Tools With Very Long Labels 0.1.0",
    );
    await expect(unsupportedRendererRow.locator(".wb-contribution-projection-state")).toHaveText(
      "Unsupported renderer: plugin.visual-review-renderer",
    );
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));

    await captureVisual(
      page,
      buildVisualName(["workbench-contributions", "panel", "ready", THEME, "desktop-tight"]),
      { ready: panel },
    );
  });

  test("source-labeled provider and plugin command autocomplete desktop-tight", async ({ page }) => {
    await installProviderCommandHeadFixture(page, commandSessionId);
    await openWorkbenchVisualPage(page, commandWorkspaceId, { theme: THEME, viewport: "desktop-tight" });
    await openFirstVisibleTaskSession(page);

    const composer = activeSessionComposer(page);
    await composer.fill("/");
    const autocomplete = page.locator(".composer-ac");
    await expect(autocomplete).toBeVisible({ timeout: 20_000 });
    const providerRow = autocompleteRow(autocomplete, "/provider-review");
    await expect(providerRow).toBeVisible({ timeout: 20_000 });
    await expect(providerRow.locator(".composer-ac-source")).toHaveText("Codex");
    const pluginRow = autocompleteRow(autocomplete, `/${VISUAL_PLUGIN_ID}:review-evidence`);
    await expect(pluginRow).toBeVisible({ timeout: 20_000 });
    await expect(pluginRow.locator(".composer-ac-source")).toHaveText("Visual Review Tools With Very Long Labels");
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await expectNoHorizontalOverflow(autocomplete);

    await captureVisual(
      page,
      buildVisualName(["workbench-commands", "source-labels", THEME, "desktop-tight"]),
      { ready: autocomplete },
    );
  });

  test("unsupported contribution diagnostics desktop-tight", async ({ page }) => {
    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "desktop-tight",
      template: "Classic",
    });

    const panel = page.getByRole("region", { name: "Workbench contributions" });
    const unsupportedRow = contributionRow(panel, "Unsupported custom review section with deliberately long source label");
    await expect(unsupportedRow).toBeVisible({ timeout: 20_000 });
    await expect(unsupportedRow.locator(".wb-contribution-projection-source")).toHaveText(
      "Visual Review Tools With Very Long Labels 0.1.0",
    );
    await expect(unsupportedRow.locator(".wb-contribution-projection-state")).toHaveText(
      "Unsupported renderer: plugin.visual-review-renderer",
    );
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));

    await captureVisual(
      page,
      buildVisualName(["workbench-contributions", "unsupported-diagnostics", THEME, "desktop-tight"]),
      { ready: panel },
    );
  });

  test("plugin contribution panel with kanban narrow layout", async ({ page }) => {
    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "narrow",
      template: "Kanban",
    });

    const panel = page.getByRole("region", { name: "Workbench contributions" });
    const detailPanel = page.locator(".wb-kanban-detail-panel");
    await expect(panel).toContainText("Visual Review Tools With Very Long Labels", { timeout: 20_000 });
    await expect(detailPanel).toBeVisible({ timeout: 20_000 });
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));

    const detailBox = await detailPanel.boundingBox();
    expect(detailBox?.height ?? 0).toBeGreaterThan(120);

    await captureVisual(
      page,
      buildVisualName(["workbench-contributions", "kanban", "narrow", THEME]),
      { ready: panel },
    );
  });

  test("classic template responsive mobile-narrow viewport", async ({ page }) => {
    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "mobile-narrow",
      template: "Classic",
    });

    await expect(page.locator(".wb-main-template-classic")).toBeVisible({ timeout: 20_000 });
    await expectNoHorizontalOverflow(page.locator(".wb-root"));
    await expectNoHorizontalOverflow(page.locator(".wb-main"));

    await captureVisual(
      page,
      buildVisualName(["workbench-template", "classic", "responsive", THEME, visualViewportLabel("mobile-narrow")]),
      { ready: page.locator(".wb-main-template-classic") },
    );
  });

  test("plugin hot reload contribution sequence desktop-tight", async ({ page, request }) => {
    await removePluginDir(visualPluginDir());
    await removePluginDir(hotReloadPluginDir());
    await reloadPluginsForVisual(request);

    await openSeededTemplateState(page, {
      workspaceId: templateWorkspaceId,
      viewport: "desktop-tight",
      template: "Classic",
    });
    const composer = activeSessionComposer(page);
    const draftText = "Draft survives plugin hot reload";
    await composer.fill(draftText);
    await expect(composer).toHaveValue(draftText);
    await expect(page.getByRole("region", { name: "Workbench contributions" })).toHaveCount(0, { timeout: 20_000 });
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await captureVisual(
      page,
      buildVisualName(["workbench-plugins", "hot-reload", "empty", THEME, "desktop-tight"]),
      { ready: page.locator(".wb-main") },
    );

    await writeHotReloadPlugin("Hot Reload Tools Initial");
    const addedInventory = await reloadPluginsForVisual(request);
    expect(addedInventory.plugins?.some((plugin) => (
      plugin.id === HOT_RELOAD_PLUGIN_ID && plugin.status === "loaded"
    ))).toBeTruthy();
    const panel = page.getByRole("region", { name: "Workbench contributions" });
    await expect(panel).toContainText("Hot Reload Tools Initial contribution panel", { timeout: 20_000 });
    await expect(panel).toContainText("Hot Reload Tools Initial 0.1.0");
    await expect(activeSessionComposer(page)).toHaveValue(draftText);
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));
    await captureVisual(
      page,
      buildVisualName(["workbench-plugins", "hot-reload", "added", THEME, "desktop-tight"]),
      { ready: panel },
    );

    await writeHotReloadPlugin("Hot Reload Tools Changed Label");
    const changedInventory = await reloadPluginsForVisual(request);
    expect(changedInventory.plugins?.some((plugin) => (
      plugin.id === HOT_RELOAD_PLUGIN_ID && plugin.status === "loaded"
    ))).toBeTruthy();
    await expect(panel).toContainText("Hot Reload Tools Changed Label contribution panel", { timeout: 20_000 });
    await expect(panel).toContainText("Hot Reload Tools Changed Label 0.1.0");
    await expect(activeSessionComposer(page)).toHaveValue(draftText);
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));
    await captureVisual(
      page,
      buildVisualName(["workbench-plugins", "hot-reload", "changed-label", THEME, "desktop-tight"]),
      { ready: panel },
    );

    const seededTemplateKey = await seedPluginTemplateSessionSelection(page, {
      workspaceId: templateWorkspaceId,
      templateId: pluginTemplateId(HOT_RELOAD_PLUGIN_ID, `${HOT_RELOAD_PLUGIN_ID}.panel`),
    });
    expect(seededTemplateKey).toMatch(/^wb\.template\.session\.v1\./);
    await page.waitForTimeout(300);
    await page.reload({ waitUntil: "domcontentloaded" });
    await waitForVisualSettled(page, { ready: activeSessionComposer(page) });
    await expect(activeSessionComposer(page)).toHaveValue(draftText);

    await removePluginDir(hotReloadPluginDir());
    await reloadPluginsForVisual(request);
    const fallbackPanel = page.getByRole("region", { name: "Workbench contributions" });
    await expect(fallbackPanel).toContainText("Plugin template fallback", { timeout: 20_000 });
    await expect(fallbackPanel).toContainText("Fallback active");
    await expect(activeSessionComposer(page)).toHaveValue(draftText);
    await expectNoHorizontalOverflow(page.locator(".wb-main"));
    await expectNoHorizontalOverflow(page.locator(".wb-contribution-projection-list"));
    await captureVisual(
      page,
      buildVisualName(["workbench-plugins", "hot-reload", "removed-fallback", THEME, "desktop-tight"]),
      { ready: fallbackPanel },
    );
  });
});
