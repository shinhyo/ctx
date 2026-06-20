import { SettingsContentRouter } from "./SettingsContentRouter";
import { SettingsShell } from "./SettingsShell";
import { useSettingsDaemonDocumentController } from "./hooks/useSettingsDaemonDocumentController";
import { useSettingsDevToolsController } from "./hooks/useSettingsDevToolsController";
import { useSettingsLocalPreferencesController } from "./hooks/useSettingsLocalPreferencesController";
import { useSettingsPageContextController } from "./hooks/useSettingsPageContextController";
import { useSettingsResourceUtilizationController } from "./hooks/useSettingsResourceUtilizationController";

export default function SettingsPage() {
  const pageContext = useSettingsPageContextController();
  const daemonSettings = useSettingsDaemonDocumentController();
  const localPreferences = useSettingsLocalPreferencesController();
  const resourceUtilization = useSettingsResourceUtilizationController({
    active: pageContext.active,
    workspaceId: pageContext.workspaceId,
    workspaces: pageContext.workspaces,
  });
  const devTools = useSettingsDevToolsController({
    enabled: pageContext.devToolsEnabled,
  });

  return (
    <SettingsShell
      backLink={pageContext.backLink}
      query={pageContext.query}
      onQueryChange={pageContext.setQuery}
      sidebarSections={pageContext.sidebarSections}
      active={pageContext.active}
      onSectionChange={pageContext.onSectionChange}
      headerLabel={pageContext.headerLabel}
      saveError={daemonSettings.saveError}
    >
      <SettingsContentRouter
        active={pageContext.active}
        workspaceId={pageContext.workspaceId}
        general={localPreferences.general}
        notifications={localPreferences.notifications}
        clientTelemetry={localPreferences.telemetry}
        daemonSettings={daemonSettings}
        themeVariant={localPreferences.themeVariant}
        resourceUtilization={resourceUtilization}
        devTools={devTools}
      />
    </SettingsShell>
  );
}
