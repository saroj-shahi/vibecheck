import { Action, ActionPanel, Icon, List, open } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { useState } from "react";
import { BUNDLE_ID, culpritRows, emptyMessage, loadStatus, vibeWord } from "./vibecheck";

export default function Command() {
  const { data, isLoading } = usePromise(loadStatus);
  const [by, setBy] = useState<"memory" | "cpu">("memory");

  if (!isLoading && data && !data.ok) {
    const m = emptyMessage(data.reason);
    return (
      <List>
        <List.EmptyView icon={Icon.QuestionMarkCircle} title={m.title} description={m.description} />
      </List>
    );
  }

  const s = data?.ok ? data.status : undefined;
  const rows = s ? culpritRows(s, by) : [];
  const copy = rows.map((x, n) => `${n + 1}. ${x.name}  ${x.detail}`).join("\n");

  return (
    <List
      isLoading={isLoading}
      navigationTitle={s ? `Culprits: ${vibeWord(s)}` : "Culprits"}
      searchBarAccessory={
        s?.topCPU?.length ? (
          <List.Dropdown tooltip="Sort by" value={by} onChange={(v) => setBy(v as "memory" | "cpu")}>
            <List.Dropdown.Item title="Memory" value="memory" />
            <List.Dropdown.Item title="CPU" value="cpu" />
          </List.Dropdown>
        ) : undefined
      }
    >
      <List.EmptyView icon={Icon.CheckCircle} title="Nothing to report yet" description={s?.verdict} />
      {rows.map((r, i) => (
        <List.Item
          key={`${i}-${r.name}`}
          icon={Icon.MemoryChip}
          title={r.name}
          accessories={[{ text: r.detail }]}
          actions={
            <ActionPanel>
              <Action title="Open VibeCheck" icon={Icon.AppWindow} onAction={() => open(BUNDLE_ID).catch(() => undefined)} />
              <Action.CopyToClipboard title="Copy Culprits" content={copy} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
