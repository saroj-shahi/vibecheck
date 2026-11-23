import { Action, ActionPanel, Color, Icon, List, open } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import {
  BUNDLE_ID,
  culpritRows,
  emptyMessage,
  forecastText,
  leftPercent,
  limitsOf,
  limitTitle,
  loadStatus,
  readings,
  resetsIn,
  statusText,
  vibeWord,
} from "./vibecheck";

const openApp = () => open(BUNDLE_ID).catch(() => undefined);

export default function Command() {
  const { data, isLoading, revalidate } = usePromise(loadStatus);

  if (!isLoading && data && !data.ok) {
    const m = emptyMessage(data.reason);
    return (
      <List>
        <List.EmptyView
          icon={Icon.QuestionMarkCircle}
          title={m.title}
          description={m.description}
          actions={
            <ActionPanel>
              <Action title="Open VibeCheck" icon={Icon.AppWindow} onAction={openApp} />
              <Action title="Try Again" icon={Icon.ArrowClockwise} onAction={revalidate} />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  const s = data?.ok ? data.status : undefined;
  const actions = s ? (
    <ActionPanel>
      <Action title="Open VibeCheck" icon={Icon.AppWindow} onAction={openApp} />
      <Action.CopyToClipboard title="Copy Status" content={statusText(s)} shortcut={{ modifiers: ["cmd"], key: "c" }} />
      <Action title="Refresh" icon={Icon.ArrowClockwise} onAction={revalidate} shortcut={{ modifiers: ["cmd"], key: "r" }} />
    </ActionPanel>
  ) : undefined;

  const vibe = s ? vibeWord(s) : "vibing";
  const color = vibe === "cooked" ? Color.Red : vibe === "mid" ? Color.Orange : Color.Green;
  const culprits = s ? culpritRows(s) : [];
  const limits = s ? limitsOf(s) : [];
  const servers = s?.devServers ?? [];

  return (
    <List isLoading={isLoading}>
      {s && (
        <>
          <List.Section title="Vibe">
            <List.Item
              icon={{ source: Icon.CircleFilled, tintColor: color }}
              title={s.verdict}
              accessories={[{ tag: { value: vibe, color } }, ...(s.stale ? [{ text: "Old news" }] : [])]}
              actions={actions}
            />
          </List.Section>
          <List.Section title="Readings">
            {readings(s).map((r) => (
              <List.Item key={r.title} title={r.title} accessories={[{ text: r.value }]} actions={actions} />
            ))}
          </List.Section>
          {culprits.length > 0 && (
            <List.Section title="Culprits">
              {culprits.map((c, i) => (
                <List.Item key={`${i}-${c.name}`} icon={Icon.MemoryChip} title={c.name} accessories={[{ text: c.detail }]} actions={actions} />
              ))}
            </List.Section>
          )}
          {limits.length > 0 && (
            <List.Section title="Agent limits">
              {limits.map((l, i) => {
                const left = leftPercent(l);
                const reset = resetsIn(l);
                return (
                  <List.Item
                    key={`${i}-${l.key ?? limitTitle(l)}`}
                    icon={Icon.Gauge}
                    title={limitTitle(l)}
                    subtitle={forecastText(l)}
                    accessories={[
                      ...(left !== undefined ? [{ text: `${left}% left` }] : []),
                      ...(reset ? [{ text: `resets in ${reset}` }] : []),
                    ]}
                    actions={actions}
                  />
                );
              })}
            </List.Section>
          )}
          {servers.length > 0 && (
            <List.Section title="Dev servers">
              {servers.map((d, i) => (
                <List.Item
                  key={`${i}-${d.pid ?? d.port ?? d.name}`}
                  icon={Icon.Network}
                  title={d.name ?? d.command ?? "Server"}
                  accessories={d.port ? [{ text: `:${d.port}` }] : []}
                  actions={actions}
                />
              ))}
            </List.Section>
          )}
        </>
      )}
    </List>
  );
}
