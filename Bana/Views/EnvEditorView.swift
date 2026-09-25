import SwiftUI

/// Edits .env text as a form (key / value, secrets hidden) or as plain text.
struct EnvEditorView: View {
    enum Mode: String, CaseIterable, Identifiable { case form, text; var id: String { rawValue } }

    let title: String
    let subtitle: String
    let original: String
    var note: String?
    let onSave: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var doc: EnvDocument
    @State private var rawText: String
    @State private var mode: Mode = .form
    @State private var query = ""
    @State private var revealed: Set<UUID> = []
    @State private var error: String?
    @State private var saved = false

    init(title: String, subtitle: String, text: String, note: String? = nil, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.original = text
        self.note = note
        self.onSave = onSave
        _doc = State(initialValue: EnvDocument(text: text))
        _rawText = State(initialValue: text)
    }

    private var currentText: String { mode == .form ? doc.text : rawText }
    private var isDirty: Bool { EnvDocument(text: currentText) != EnvDocument(text: original) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title2).foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head).ltr()
                }
                Spacer()
                Picker("", selection: $mode) {
                    Text(tr("فرم", "Form")).tag(Mode.form)
                    Text(tr("متن", "Text")).tag(Mode.text)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(16)

            if let note {
                Label(note.rtl, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Divider()

            Group {
                switch mode {
                case .form: formEditor
                case .text: textEditor
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                if let error {
                    Label(error.rtl, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2)
                } else if saved {
                    Label(tr("ذخیره شد", "Saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button(tr("بستن", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("ذخیره", "Save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s")
                    .disabled(!isDirty && saved)
            }
            .padding(14)
        }
        .frame(width: 720, height: 600)
        .onChange(of: mode) { newMode in
            // Carry edits across the two views.
            if newMode == .text { rawText = doc.text } else { doc = EnvDocument(text: rawText) }
        }
    }

    // MARK: Form

    private var formEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("جست‌وجوی متغیر", "Filter variables"), text: $query).textFieldStyle(.plain)
                Spacer()
                Button { addVariable() } label: { Label(tr("متغیر تازه", "Add Variable"), systemImage: "plus") }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($doc.lines) { $line in
                            if matches(line) { row($line).id(line.id) }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: doc.lines.count) { _ in
                    if let last = doc.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .ltr() // keys and values are code
        }
    }

    @ViewBuilder
    private func row(_ line: Binding<EnvDocument.Line>) -> some View {
        let l = line.wrappedValue
        if l.isEntry {
            HStack(spacing: 8) {
                TextField("KEY", text: line.key)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .textFieldStyle(.plain)
                    .frame(width: 230, alignment: .leading)
                Group {
                    if l.isSecret && !revealed.contains(l.id) {
                        SecureField("", text: line.value)
                    } else {
                        TextField("", text: line.value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                if l.isSecret {
                    Button {
                        if revealed.contains(l.id) { revealed.remove(l.id) } else { revealed.insert(l.id) }
                    } label: {
                        Image(systemName: revealed.contains(l.id) ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(tr("نمایش/پنهان کردن", "Show / hide"))
                } else {
                    Color.clear.frame(width: 16)
                }
                Button(role: .destructive) {
                    doc.lines.removeAll { $0.id == l.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(tr("حذف", "Remove"))
            }
            .padding(.horizontal, 16).padding(.vertical, 3)
        } else if l.raw.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 8)
        } else {
            Text(l.raw)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)
        }
    }

    private func matches(_ line: EnvDocument.Line) -> Bool {
        guard !query.isEmpty else { return true }
        return line.isEntry && (line.key.localizedCaseInsensitiveContains(query) || line.value.localizedCaseInsensitiveContains(query))
    }

    private func addVariable() {
        query = ""
        doc.lines.append(EnvDocument.Line(key: "NEW_VARIABLE", value: "", raw: ""))
    }

    // MARK: Text

    private var textEditor: some View {
        TextEditor(text: $rawText)
            .font(.system(size: 12.5, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .ltr()
    }

    private func save() {
        let keys = EnvDocument(text: currentText).lines.filter(\.isEntry).map(\.key)
        if let bad = keys.first(where: { $0.contains(" ") && !$0.hasPrefix("export ") }) {
            error = tr("نام متغیر فاصله دارد: \(bad)", "Variable name contains a space: \(bad)")
            return
        }
        do {
            try onSave(currentText)
            error = nil
            saved = true
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The project's own .env files: pick one, edit, save to disk.
struct LocalEnvSheet: View {
    let project: Project
    let isRunning: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var editing: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("فایل‌های \(lrm(".env"))", ".env Files").rtl).font(.title3.weight(.semibold))
                    Text(project.name).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(files, id: \.self) { url in
                    Button { editing = url } label: {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            Text(relative(url)).font(.body.monospaced()).ltr()
                            Spacer()
                            if url.lastPathComponent == ".env" {
                                Text(tr("فعال", "Active")).font(.caption.weight(.semibold)).foregroundStyle(.green)
                            }
                            Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
                if let example = exampleToCopy {
                    Button {
                        let env = project.url.appendingPathComponent(".env")
                        try? EnvFiles.write((try? String(contentsOf: example, encoding: .utf8)) ?? "", to: env)
                        reload()
                        editing = env
                    } label: {
                        Label(tr("ساخت \(lrm(".env")) از روی \(lrm(example.lastPathComponent))", "Create .env from \(example.lastPathComponent)"), systemImage: "plus.circle")
                    }
                }
                if files.isEmpty && exampleToCopy == nil {
                    Text(tr("این پروژه فایل \(lrm(".env")) ندارد.", "This project has no .env file.").rtl).foregroundStyle(.secondary)
                }
                if isRunning {
                    Label(tr("تغییرات بعد از اجرای دوبارهٔ سرور اعمال می‌شوند.", "Changes apply after the server restarts."), systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack { Spacer(); Button(tr("بستن", "Close")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(14)
        }
        .frame(width: 540, height: 480)
        .onAppear(perform: reload)
        .sheet(item: $editing) { url in
            EnvEditorView(title: url.lastPathComponent, subtitle: url.path,
                          text: (try? String(contentsOf: url, encoding: .utf8)) ?? "",
                          note: url.lastPathComponent.contains("example")
                            ? tr("این فایل نمونه است و معمولاً در git ثبت می‌شود — رمز واقعی در آن ننویسید.", "This is a template, usually committed to git — don't put real passwords in it.")
                            : nil) { text in
                try EnvFiles.write(text, to: url)
            }
            .localizedUI()
        }
    }

    private var exampleToCopy: URL? {
        guard !files.contains(where: { $0.lastPathComponent == ".env" && $0.deletingLastPathComponent() == project.url }) else { return nil }
        return files.first { $0.lastPathComponent == ".env.example" && $0.deletingLastPathComponent() == project.url }
    }

    private func reload() { files = EnvFiles.find(in: project.url) }

    private func relative(_ url: URL) -> String { String(url.path.dropFirst(project.url.path.count + 1)) }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
