import SwiftUI
import TCRoofUI
import TCRoofCore

/// A form screen: the questions and, beside them (iPad) or on the second tab (iPhone), the pages as they will print.
struct PermitFormScaffold<Questions: View>: View {
    let title: String
    let job: Job
    let map: PermitFormMap
    let issues: [String]
    let fileName: String
    let content: () -> PermitRenderer.Content
    /// Changes whenever an answer changes; the preview redraws on it.
    let version: AnyHashable
    let form: Questions

    @State private var pane = "กรอกข้อมูล"
    @State private var shareURL: ShareItem?

    init(title: String, job: Job, map: PermitFormMap, issues: [String], fileName: String, version: AnyHashable,
         content: @escaping () -> PermitRenderer.Content, @ViewBuilder form: () -> Questions) {
        self.title = title; self.job = job; self.map = map; self.issues = issues; self.fileName = fileName
        self.version = version; self.content = content; self.form = form()
    }

    var body: some View {
        VStack(spacing: 0) {
            TCNavBar(title: title, trail: ["หน้าหลัก", job.code, "เอกสารขออนุญาต PEA"], current: title) {
                TCButton("ส่งออก PDF", systemImage: "square.and.arrow.up", kind: .secondary, size: .card) { export() }
            }
            if isPhone {
                TCSegmented(["กรอกข้อมูล", "ดูเอกสาร"], selection: $pane)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                if pane == "กรอกข้อมูล" { formColumn } else { PermitPagesPreview(map: map, version: version, content: content) }
            } else {
                HStack(spacing: 0) {
                    formColumn.frame(width: 470)
                    Rectangle().fill(Theme.borderSubtle).frame(width: 1)
                    PermitPagesPreview(map: map, version: version, content: content)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareURL) { ActivitySheet(items: [$0.url]) }
    }

    private var formColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                PermitIssuesCard(issues: issues)
                form
            }
            .padding(Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func export() {
        guard let data = PermitRenderer.pdf(map, content()),
              let url = PermitStore(job: job).exportURL(data, fileName: fileName) else { return }
        shareURL = ShareItem(url: url)
    }

    struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }
}

/// The pages drawn exactly as they will print, redrawn shortly after the answers stop changing.
struct PermitPagesPreview: View {
    let map: PermitFormMap
    let version: AnyHashable
    let content: () -> PermitRenderer.Content

    @State private var images: [Int: UIImage] = [:]

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 2 * Space.l, 760)
            ScrollView {
                LazyVStack(spacing: Space.l) {
                    ForEach(0..<map.pages, id: \.self) { i in
                        page(i, width: width)
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.paperPage)
        .task(id: version) {
            try? await Task.sleep(for: .milliseconds(images.isEmpty ? 0 : 300))
            guard !Task.isCancelled else { return }
            let c = content()
            let doc = PermitRenderer.document(map)
            for i in 0..<map.pages {
                guard !Task.isCancelled else { return }
                images[i] = PermitRenderer.image(page: i, map, c, document: doc)
                await Task.yield()
            }
        }
    }

    private func page(_ i: Int, width: CGFloat) -> some View {
        let size = PermitRenderer.pageSize(map)
        return VStack(alignment: .leading, spacing: Space.xs) {
            if map.pages > 1 {
                Text("หน้า \(i + 1)/\(map.pages)").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            Group {
                if let image = images[i] {
                    Image(uiImage: image).resizable().interpolation(.high)
                } else {
                    Color.white.overlay(ProgressView())
                }
            }
            .frame(width: width, height: width * size.height / size.width)
            .shadow(color: Theme.navy.opacity(0.12), radius: 6, y: 2)
            .accessibilityLabel("ตัวอย่างเอกสาร หน้า \(i + 1)")
        }
    }
}

/// `ครบแล้ว` or what is still missing.
struct PermitIssuesCard: View {
    let issues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("ความครบถ้วน").font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                if issues.isEmpty {
                    TCStatusChip("ครบ พร้อมพิมพ์", kind: .done, dot: true)
                } else {
                    TCStatusChip("ขาด \(issues.count) รายการ", kind: .pending, dot: true)
                }
            }
            if !issues.isEmpty {
                Text(issues.joined(separator: " · "))
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.l)
    }
}

/// A titled card of questions.
struct PermitSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.l)
    }
}

/// Label over a text field, with an optional error line under it.
struct PermitField: View {
    let title: String
    @Binding var text: String
    var required = false
    var keyboard: UIKeyboardType = .default
    var unit: String?
    var error: String?

    init(_ title: String, text: Binding<String>, required: Bool = false, keyboard: UIKeyboardType = .default,
         unit: String? = nil, error: String? = nil) {
        self.title = title; self._text = text; self.required = required; self.keyboard = keyboard; self.unit = unit; self.error = error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TCFieldLabel(title, required: required)
            TCTextField(title, text: $text, unit: unit, required: required, keyboard: keyboard)
            if let error {
                Text(error).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
            }
        }
    }
}

/// Two fields side by side on iPad, stacked on iPhone.
struct PermitRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if isPhone {
            VStack(alignment: .leading, spacing: Space.m) { content }
        } else {
            HStack(alignment: .top, spacing: Space.m) { content }
        }
    }
}
