import { Color, Icon, MenuBarExtra, open } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { BUNDLE_ID, culpritRows, emptyMessage, loadStatus, readings, vibeWord } from "./vibecheck";

const openApp = () => open(BUNDLE_ID).catch(() => undefined);

export default function Command() {
  const { data, isLoading } = usePromise(loadStatus);

  if (!data?.ok) {
    return (
      <MenuBarExtra icon={Icon.CircleDisabled} isLoading={isLoading} tooltip="VibeCheck">
        {data && <MenuBarExtra.Item title={emptyMessage(data.reason).title} />}
        <MenuBarExtra.Item title="Open VibeCheck" onAction={openApp} />
      </MenuBarExtra>
    );
  }

  const s = data.status;
  const vibe = vibeWord(s);
  const color = vibe === "cooked" ? Color.Red : vibe === "mid" ? Color.Orange : Color.Green;
  const culprits = culpritRows(s).slice(0, 3);

  return (
    <MenuBarExtra icon={{ source: Icon.CircleFilled, tintColor: color }} title={vibe} tooltip={s.verdict} isLoading={isLoading}>
      <MenuBarExtra.Section>
        <MenuBarExtra.Item title={s.verdict} />
      </MenuBarExtra.Section>
      <MenuBarExtra.Section title="Readings">
        {readings(s)
          .slice(0, 5)
          .map((r) => (
            <MenuBarExtra.Item key={r.title} title={`${r.title}: ${r.value}`} />
          ))}
      </MenuBarExtra.Section>
      {culprits.length > 0 && (
        <MenuBarExtra.Section title="Culprits">
          {culprits.map((c, i) => (
            <MenuBarExtra.Item key={`${i}-${c.name}`} title={`${c.name}  ${c.detail}`} />
          ))}
        </MenuBarExtra.Section>
      )}
      <MenuBarExtra.Section>
        <MenuBarExtra.Item title="Open VibeCheck" onAction={openApp} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
