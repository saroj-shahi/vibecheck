import SwiftUI

struct DiskPanel: View {
    @Environment(SystemStats.self) private var stats

    var body: some View {
        let d = stats.disk
        let primary = stats.volumes.first { $0.path == "/" } ?? stats.volumes.first
        Panel(module: .disk, headline: primary.map { Fmt.percent($0.usage) } ?? "—",
              subtitle: primary.map { "\(Fmt.bytes($0.available)) free" }) {
            MetricChart(lines: [.init(key: .read, color: Palette.read, name: "R"),
                                .init(key: .write, color: Palette.write, name: "W")],
                        mirrored: true, height: 80, format: Fmt.rate)
            HStack {
                Text("Read \(Fmt.rate(d.readRate))").foregroundStyle(Palette.read)
                Spacer()
                Text("Write \(Fmt.rate(d.writeRate))").foregroundStyle(Palette.write)
            }
            .font(.caption.monospacedDigit())

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Volumes")
                ForEach(stats.volumes) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(v.name).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.bytes(v.available)) free").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                        CapacityBar(fraction: v.usage, color: Palette.level(v.usage))
                            .help("\(Fmt.bytes(v.used)) of \(Fmt.bytes(v.total)) used")
                    }
                }
            }
        }
    }
}

