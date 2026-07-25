import AppKit
import BarStateCore
import SwiftUI

private struct EditorRequestConfiguration: Equatable {
    let urlString: String
    let requestHeaders: [RequestHeader]

    init(monitor: Monitor) {
        urlString = monitor.urlString
        requestHeaders = monitor.requestHeaders
    }
}

private struct EditorTestConfiguration: Equatable {
    let request: EditorRequestConfiguration
    let parser: ParserConfiguration

    init(monitor: Monitor) {
        request = EditorRequestConfiguration(monitor: monitor)
        parser = monitor.parser
    }
}

private struct EditorRequestFailure: Equatable {
    let message: String
    let attemptedAt: Date
}

private enum RequestHeaderLayoutMetrics {
    static let columnSpacing: CGFloat = 10
    static let actionSize: CGFloat = 28
    static let actionsWidth = actionSize * 2 + columnSpacing
}

private struct EditorEditableConfiguration: Equatable {
    let name: String
    let urlString: String
    let requestHeaders: [RequestHeader]
    let parser: ParserConfiguration
    let displayTemplate: String
    let refreshInterval: TimeInterval
    let refreshIntervalUnit: RefreshIntervalUnit

    init(monitor: Monitor) {
        name = monitor.name
        urlString = monitor.urlString
        requestHeaders = monitor.requestHeaders
        parser = monitor.parser
        displayTemplate = monitor.displayTemplate
        refreshInterval = monitor.refreshInterval
        refreshIntervalUnit = monitor.refreshIntervalUnit
    }
}

struct MonitorEditorViewV2: View {
    @State private var draft: Monitor
    @State private var refreshIntervalValue: Double
    @State private var baselineParser: ParserConfiguration
    @State private var baselineConfiguration: EditorEditableConfiguration
    @State private var requiresInitialSuccessfulTest: Bool
    @State private var validationMessage: String?
    @State private var savedMessage: String?

    @State private var response: HTTPResponseSnapshot?
    @State private var responseConfiguration: EditorRequestConfiguration?
    @State private var usesManualResponse = false
    @State private var isRequesting = false
    @State private var requestMessage: String?
    @State private var requestFailure: EditorRequestFailure?
    @State private var requestTask: Task<Void, Never>?

    @State private var isParsing = false
    @State private var parseMessage: String?
    @State private var parseSucceeded = false
    @State private var successfulTestConfiguration: EditorTestConfiguration?
    @State private var parseTask: Task<Void, Never>?

    @State private var copiedVariable: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var revealedHeaderIDs: Set<UUID> = []

    let latestRuntime: MonitorRuntimeState
    let isRefreshing: Bool
    let nextRefreshAt: Date?
    let onDirtyChange: (Bool) -> Void
    let onSwitchesChange: ((Bool, Bool) -> Void)?
    let onCancel: () -> Void
    let onSave: (Monitor) -> Void

    init(
        monitor: Monitor,
        requiresInitialSuccessfulTest: Bool = false,
        isRefreshing: Bool = false,
        nextRefreshAt: Date? = nil,
        onDirtyChange: @escaping (Bool) -> Void = { _ in },
        onSwitchesChange: ((Bool, Bool) -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Monitor) -> Void
    ) {
        var editableMonitor = monitor
        editableMonitor.parser.scriptBody = JavaScriptEvaluator.updatingResponseType(
            in: monitor.parser.scriptBody,
            bodyKind: monitor.runtime.lastResponse?.bodyKind
        )
        if let bodyKind = monitor.runtime.lastResponse?.bodyKind,
           bodyKind != .json,
           editableMonitor.parser.kind == .jsonPath
        {
            editableMonitor.parser.kind = .javaScript
        }

        _draft = State(initialValue: editableMonitor)
        _refreshIntervalValue = State(
            initialValue: editableMonitor.refreshIntervalUnit.value(
                for: editableMonitor.refreshInterval
            )
        )
        _baselineParser = State(initialValue: editableMonitor.parser)
        _baselineConfiguration = State(
            initialValue: EditorEditableConfiguration(monitor: editableMonitor)
        )
        _requiresInitialSuccessfulTest = State(initialValue: requiresInitialSuccessfulTest)
        _response = State(initialValue: monitor.runtime.lastResponse)
        _responseConfiguration = State(
            initialValue: monitor.runtime.lastResponse == nil
                ? nil
                : EditorRequestConfiguration(monitor: editableMonitor)
        )

        latestRuntime = monitor.runtime
        self.isRefreshing = isRefreshing
        self.nextRefreshAt = nextRefreshAt
        self.onDirtyChange = onDirtyChange
        self.onSwitchesChange = onSwitchesChange
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        titleBar
                        runtimeStatus

                        settingsSection(L10n.string("editor.section.basic")) {
                            formGrid {
                                GridRow {
                                    fieldLabel(L10n.string("common.name"))
                                    TextField(
                                        L10n.string("editor.name_placeholder"),
                                        text: $draft.name
                                    )
                                    .accessibilityLabel(L10n.string("common.name"))
                                }
                                GridRow(alignment: .top) {
                                    fieldLabel(L10n.string("editor.display_template"))
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField(
                                            L10n.string("editor.template_placeholder"),
                                            text: $draft.displayTemplate
                                        )
                                        .accessibilityLabel(L10n.string("editor.display_template"))
                                        displayTemplateHelp
                                    }
                                }
                            }
                        }

                        settingsSection(L10n.string("editor.section.request")) {
                            VStack(alignment: .leading, spacing: 14) {
                                formGrid {
                                    GridRow {
                                        fieldLabel("HTTPS URL")
                                        TextField(
                                            "https://api.example.com/value?ts=${TIMESTAMP}",
                                            text: $draft.urlString
                                        )
                                        .textContentType(.URL)
                                        .accessibilityLabel("HTTPS URL")
                                    }
                                    GridRow {
                                        fieldLabel(L10n.string("editor.refresh_interval"))
                                        HStack(spacing: 12) {
                                            TextField(
                                                L10n.string("editor.numeric_value"),
                                                value: refreshIntervalValueBinding,
                                                format: .number.precision(.fractionLength(0...6))
                                            )
                                            .frame(width: 120)
                                            .accessibilityLabel(
                                                L10n.string("editor.refresh_interval_value_accessibility")
                                            )

                                            Picker(
                                                L10n.string("editor.refresh_interval_unit"),
                                                selection: refreshIntervalUnitBinding
                                            ) {
                                                ForEach(RefreshIntervalUnit.allCases) { unit in
                                                    Text(unit.displayName).tag(unit)
                                                }
                                            }
                                            .pickerStyle(.segmented)
                                            .labelsHidden()
                                            .frame(width: 220)
                                        }
                                    }
                                }

                                requestHeadersSection
                                requestActionRow
                                ResponsePreviewView(
                                    response: response,
                                    isLoading: isRequesting,
                                    isConfigurationStale: isResponseStale,
                                    sourceLabel: responseSourceLabel,
                                    latestRequestFailure: requestFailure
                                )
                            }
                        }

                        settingsSection(L10n.string("editor.section.parser")) {
                            parserSection
                        }
                        .id("parser-section")
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    guard ProcessInfo.processInfo.arguments.contains("--preview-parser") else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("parser-section", anchor: .top)
                    }
                }
            }

            editorActions
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--preview-request-failure") {
                let message = L10n.string("editor.preview_network_error")
                requestMessage = message
                requestFailure = EditorRequestFailure(message: message, attemptedAt: Date())
            }
            if arguments.contains("--preview-parse-success") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    testParsing()
                }
            }
        }
        .onDisappear {
            requestTask?.cancel()
            parseTask?.cancel()
            copyFeedbackTask?.cancel()
        }
        .onChange(of: currentRequestConfiguration) {
            requestTask?.cancel()
            requestTask = nil
            isRequesting = false
            requestMessage = nil
            requestFailure = nil
            resetParseFeedback()
            savedMessage = nil
        }
        .onChange(of: draft.parser) {
            parseTask?.cancel()
            parseTask = nil
            isParsing = false
            resetParseFeedback()
            savedMessage = nil
        }
        .onChange(of: currentEditableConfiguration) {
            savedMessage = nil
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: latestRuntime.lastResponse) { _, newResponse in
            guard !usesManualResponse, let newResponse else { return }
            response = newResponse
            responseConfiguration = currentRequestConfiguration
            requestFailure = nil
        }
    }

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 24) {
            Text(L10n.string("editor.title"))
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 24)

            HStack(spacing: 18) {
                Toggle(L10n.string("editor.enable_monitor"), isOn: isEnabledBinding)
                Toggle(L10n.string("editor.show_in_menu_bar"), isOn: showsInMenuBarBinding)
            }
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    private var runtimeStatus: some View {
        MonitorRuntimeStatusView(
            runtime: latestRuntime,
            isRefreshing: isRefreshing,
            nextRefreshAt: nextRefreshAt,
            isEnabled: draft.isEnabled,
            isSavedMonitor: switchesApplyImmediately
        )
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.headline)
                    .fixedSize()
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.65))
                    .frame(height: 1)
            }
            content()
        }
    }

    private func formGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            content()
        }
    }

    private var displayTemplateHelp: some View {
        HStack(spacing: 6) {
            Text(L10n.string("editor.template_insert_prefix"))
            variableButton(Monitor.valuePlaceholder)
            Text(L10n.string("editor.template_insert_suffix"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var requestHeadersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("editor.request_headers"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L10n.string("editor.add_request_header")) {
                    draft.requestHeaders.append(RequestHeader())
                }
            }

            if draft.requestHeaders.isEmpty {
                Label(L10n.string("editor.no_request_headers"), systemImage: "tray")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                HStack(spacing: RequestHeaderLayoutMetrics.columnSpacing) {
                    Text(L10n.string("common.name"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.string("common.value"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: RequestHeaderLayoutMetrics.actionsWidth, height: 1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach($draft.requestHeaders) { $header in
                HStack(spacing: RequestHeaderLayoutMetrics.columnSpacing) {
                    TextField("Authorization", text: $header.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(
                            L10n.string("editor.request_header_name_accessibility")
                        )

                    Group {
                        if !header.hasSensitiveValue || revealedHeaderIDs.contains(header.id) {
                            TextField("Bearer ${TIMESTAMP}", text: $header.value)
                        } else {
                            SecureField("Bearer ${TIMESTAMP}", text: $header.value)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(L10n.format(
                        "editor.request_header_value_accessibility",
                        localizedHeaderName(for: header)
                    ))

                    Group {
                        if header.hasSensitiveValue {
                            Button {
                                if revealedHeaderIDs.contains(header.id) {
                                    revealedHeaderIDs.remove(header.id)
                                } else {
                                    revealedHeaderIDs.insert(header.id)
                                }
                            } label: {
                                Image(systemName: revealedHeaderIDs.contains(header.id) ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(
                                revealedHeaderIDs.contains(header.id)
                                    ? L10n.string("editor.hide_header_value")
                                    : L10n.string("editor.show_header_value")
                            )
                            .accessibilityLabel(
                                revealedHeaderIDs.contains(header.id)
                                    ? L10n.format(
                                        "editor.hide_named_header_value",
                                        localizedHeaderName(for: header)
                                    )
                                    : L10n.format(
                                        "editor.show_named_header_value",
                                        localizedHeaderName(for: header)
                                    )
                            )
                        } else {
                            Color.clear
                        }
                    }
                    .frame(
                        width: RequestHeaderLayoutMetrics.actionSize,
                        height: RequestHeaderLayoutMetrics.actionSize
                    )

                    Button {
                        draft.requestHeaders.removeAll { $0.id == header.id }
                        revealedHeaderIDs.remove(header.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .frame(
                        width: RequestHeaderLayoutMetrics.actionSize,
                        height: RequestHeaderLayoutMetrics.actionSize
                    )
                    .help(L10n.string("editor.delete_header"))
                    .accessibilityLabel(L10n.format(
                        "editor.delete_named_header",
                        localizedHeaderName(for: header)
                    ))
                }
                .onChange(of: header.name) {
                    revealedHeaderIDs.remove(header.id)
                }
            }

            HStack(spacing: 7) {
                Text(L10n.string("editor.available_variables"))
                    .foregroundStyle(.secondary)
                variableButton(RequestTemplateResolver.timestampPlaceholder)
                Text(L10n.string("editor.unix_timestamp"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.background.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private var requestActionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(
                isRequesting
                    ? L10n.string("editor.requesting")
                    : L10n.string("editor.test_request")
            ) {
                testRequest()
            }
            .disabled(isRequesting)

            if isRequesting {
                ProgressView()
                    .controlSize(.small)
            } else if let requestMessage {
                Label(requestMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var parserSection: some View {
        formGrid {
            GridRow {
                fieldLabel(L10n.string("editor.parser_type"))
                Picker(L10n.string("editor.parser_type"), selection: $draft.parser.kind) {
                    Text(ParserKind.jsonPath.displayName)
                        .tag(ParserKind.jsonPath)
                        .disabled(!isJSONPathAvailable)
                    Text(ParserKind.javaScript.displayName)
                        .tag(ParserKind.javaScript)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
            }

            GridRow(alignment: .top) {
                fieldLabel(L10n.string("editor.parser_expression"))
                VStack(alignment: .leading, spacing: 8) {
                    if draft.parser.kind == .jsonPath {
                        TextField("$.data.items[0].value", text: $draft.parser.jsonPath)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityLabel(L10n.string("editor.jsonpath_accessibility"))
                        Text(L10n.string("editor.jsonpath_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextEditor(text: $draft.parser.scriptBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150)
                            .padding(6)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator.opacity(0.7), lineWidth: 1)
                            }
                            .accessibilityLabel(L10n.string("editor.javascript_accessibility"))
                    }
                }
            }

            GridRow(alignment: .top) {
                Color.clear.frame(width: 100, height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Button(
                        isParsing
                            ? L10n.string("editor.parsing")
                            : L10n.string("editor.test_parser")
                    ) {
                        testParsing()
                    }
                    .disabled(!canTestParsing)

                    if isParsing {
                        ProgressView()
                            .controlSize(.small)
                    } else if let parseMessage {
                        Text(parseMessage)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(parseSucceeded ? Color.green : Color.red)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
        }
    }

    private var editorActions: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let saveRequirementMessage {
                    Text(saveRequirementMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(cancelButtonTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(!hasUnsavedChanges)
                Button(L10n.string("common.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    !hasUnsavedChanges
                        || isRequesting
                        || isParsing
                        || isSuccessfulTestRequiredAndMissing
                )
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 14)
        }
        .background(.bar)
    }

    private var cancelButtonTitle: String {
        switchesApplyImmediately
            ? L10n.string("editor.restore_changes")
            : L10n.string("editor.cancel_new")
    }

    private func variableButton(_ variable: String) -> some View {
        Button {
            copyVariable(variable)
        } label: {
            HStack(spacing: 5) {
                Text(variable)
                    .font(.system(.caption, design: .monospaced))
                Image(systemName: copiedVariable == variable ? "checkmark" : "doc.on.doc")
                    .imageScale(.small)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(copiedVariable == variable ? Color.green : Color.accentColor)
        .help(
            copiedVariable == variable
                ? L10n.string("editor.copied")
                : L10n.format("editor.copy_variable", variable)
        )
        .accessibilityLabel(L10n.format("editor.copy_variable", variable))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 100, alignment: .trailing)
    }

    private func localizedHeaderName(for header: RequestHeader) -> String {
        header.name.isEmpty
            ? L10n.string("editor.request_header_unnamed")
            : header.name
    }

    private var currentRequestConfiguration: EditorRequestConfiguration {
        EditorRequestConfiguration(monitor: draft)
    }

    private var currentTestConfiguration: EditorTestConfiguration {
        EditorTestConfiguration(monitor: draft)
    }

    private var currentEditableConfiguration: EditorEditableConfiguration {
        EditorEditableConfiguration(monitor: draft)
    }

    private var responseSourceLabel: String {
        guard response != nil else { return L10n.string("editor.response_preview") }
        return usesManualResponse
            ? L10n.string("editor.manual_response")
            : L10n.string("editor.latest_response")
    }

    private var hasUnsavedChanges: Bool {
        requiresInitialSuccessfulTest || currentEditableConfiguration != baselineConfiguration
    }

    private var switchesApplyImmediately: Bool {
        onSwitchesChange != nil
    }

    private var requiresSuccessfulTest: Bool {
        requiresInitialSuccessfulTest || draft.parser != baselineParser
    }

    private var isSuccessfulTestRequiredAndMissing: Bool {
        requiresSuccessfulTest && successfulTestConfiguration != currentTestConfiguration
    }

    private var saveRequirementMessage: String? {
        guard isSuccessfulTestRequiredAndMissing else { return nil }
        if requiresInitialSuccessfulTest {
            return L10n.string("editor.new_monitor_test_required")
        }
        return L10n.string("editor.parser_retest_required")
    }

    private var isResponseStale: Bool {
        guard response != nil else { return false }
        return responseConfiguration != currentRequestConfiguration
    }

    private var isJSONPathAvailable: Bool {
        guard let response else { return true }
        return response.bodyKind == .json
    }

    private var canTestParsing: Bool {
        guard response != nil,
              !isResponseStale,
              requestFailure == nil,
              !isRequesting,
              !isParsing
        else { return false }
        guard response?.bodyKind != .binary else { return false }
        return draft.parser.kind != .jsonPath || isJSONPathAvailable
    }

    private var refreshIntervalValueBinding: Binding<Double> {
        Binding(
            get: { refreshIntervalValue },
            set: { newValue in
                refreshIntervalValue = newValue
                draft.refreshInterval = draft.refreshIntervalUnit.seconds(for: newValue)
            }
        )
    }

    private var refreshIntervalUnitBinding: Binding<RefreshIntervalUnit> {
        Binding(
            get: { draft.refreshIntervalUnit },
            set: { newUnit in
                draft.refreshIntervalUnit = newUnit
                draft.refreshInterval = newUnit.seconds(for: refreshIntervalValue)
            }
        )
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.isEnabled },
            set: { newValue in
                draft.isEnabled = newValue
                applySwitchesImmediatelyIfSaved()
            }
        )
    }

    private var showsInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { draft.showsInMenuBar },
            set: { newValue in
                draft.showsInMenuBar = newValue
                applySwitchesImmediatelyIfSaved()
            }
        )
    }

    private func applySwitchesImmediatelyIfSaved() {
        guard let onSwitchesChange else { return }
        onSwitchesChange(draft.isEnabled, draft.showsInMenuBar)
        validationMessage = nil
        savedMessage = L10n.string("editor.switches_applied")
    }

    private func testRequest() {
        do {
            try validateRequestConfiguration()
        } catch {
            requestMessage = error.localizedDescription
            return
        }

        requestTask?.cancel()
        parseTask?.cancel()
        isParsing = false
        resetParseFeedback()
        requestMessage = nil
        requestFailure = nil
        isRequesting = true
        let monitor = draft
        let configuration = currentRequestConfiguration

        requestTask = Task {
            let outcome = await APIClient().request(for: monitor)
            guard !Task.isCancelled else { return }
            isRequesting = false
            requestTask = nil

            if let receivedResponse = outcome.response {
                response = receivedResponse
                responseConfiguration = configuration
                usesManualResponse = true
                requestFailure = nil
                draft.parser.scriptBody = JavaScriptEvaluator.updatingResponseType(
                    in: draft.parser.scriptBody,
                    bodyKind: receivedResponse.bodyKind
                )
                if receivedResponse.bodyKind != .json, draft.parser.kind == .jsonPath {
                    draft.parser.kind = .javaScript
                }
            } else if let error = outcome.error {
                requestFailure = EditorRequestFailure(
                    message: error.localizedDescription,
                    attemptedAt: outcome.requestedAt
                )
            }
            requestMessage = outcome.error?.localizedDescription
        }
    }

    private func testParsing() {
        guard let response, !isResponseStale else { return }
        do {
            try validateParserConfiguration()
        } catch {
            parseSucceeded = false
            parseMessage = error.localizedDescription
            successfulTestConfiguration = nil
            return
        }

        parseTask?.cancel()
        isParsing = true
        parseMessage = nil
        parseSucceeded = false
        successfulTestConfiguration = nil
        let monitor = draft
        let configuration = currentTestConfiguration

        parseTask = Task {
            let result = await APIClient().parseValue(from: response, for: monitor)
            guard !Task.isCancelled else { return }
            isParsing = false
            parseTask = nil

            switch result {
            case let .success(value):
                let valueText = NumberDisplayFormatter.string(from: value)
                if isSuccessfulHTTPResponse(response) {
                    parseSucceeded = true
                    parseMessage = valueText
                    successfulTestConfiguration = configuration
                } else {
                    parseSucceeded = false
                    let statusText = response.statusText
                        ?? L10n.string("editor.unsuccessful_status")
                    parseMessage = L10n.format(
                        "editor.parsed_non_success",
                        valueText,
                        statusText
                    )
                    successfulTestConfiguration = nil
                }
            case let .failure(error):
                parseSucceeded = false
                parseMessage = error.localizedDescription
                successfulTestConfiguration = nil
            }
        }
    }

    private func resetParseFeedback() {
        parseMessage = nil
        parseSucceeded = false
        successfulTestConfiguration = nil
    }

    private func copyVariable(_ variable: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(variable, forType: .string) else { return }

        copiedVariable = variable
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedVariable = nil
            copyFeedbackTask = nil
        }
    }

    private func save() {
        do {
            try validate()
            draft.requestHeaders = draft.requestHeaders.map { header in
                var normalized = header
                normalized.name = header.normalizedName
                return normalized
            }
            validationMessage = nil
            savedMessage = L10n.string("editor.saved")
            baselineParser = draft.parser
            baselineConfiguration = EditorEditableConfiguration(monitor: draft)
            requiresInitialSuccessfulTest = false
            onSave(draft)
            onDirtyChange(false)
        } catch {
            savedMessage = nil
            validationMessage = error.localizedDescription
        }
    }

    private func validate() throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorValidationErrorV2(L10n.string("editor.validation.name_required"))
        }
        guard draft.refreshInterval.isFinite,
              draft.refreshInterval >= Monitor.minimumRefreshInterval
        else {
            throw EditorValidationErrorV2(L10n.string("editor.validation.interval_min"))
        }
        guard draft.refreshInterval <= Monitor.maximumRefreshInterval else {
            throw EditorValidationErrorV2(L10n.string("editor.validation.interval_max"))
        }
        guard draft.displayTemplate.contains(Monitor.valuePlaceholder) else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.template_value_required")
            )
        }

        try validateRequestConfiguration()
        try validateParserConfiguration()

        guard !isSuccessfulTestRequiredAndMissing else {
            throw EditorValidationErrorV2(
                saveRequirementMessage ?? L10n.string("editor.validation.test_required")
            )
        }
    }

    private func validateRequestConfiguration() throws {
        let validationDate = Date()
        let resolvedURLString = RequestTemplateResolver.resolve(draft.urlString, at: validationDate)
        guard let components = URLComponents(string: resolvedURLString),
              components.scheme?.lowercased() == "https",
              components.host != nil
        else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.valid_https_url")
            )
        }

        var headerNames: Set<String> = []
        for header in draft.requestHeaders {
            let resolvedHeader = RequestHeader(
                name: RequestTemplateResolver.resolve(header.name, at: validationDate),
                value: RequestTemplateResolver.resolve(header.value, at: validationDate)
            )
            guard !resolvedHeader.normalizedName.isEmpty else {
                throw EditorValidationErrorV2(
                    L10n.string("editor.validation.header_name_required")
                )
            }
            guard resolvedHeader.isValid else {
                throw EditorValidationErrorV2(
                    L10n.format("editor.validation.header_invalid", header.name)
                )
            }
            guard headerNames.insert(resolvedHeader.normalizedName.lowercased()).inserted else {
                throw EditorValidationErrorV2(
                    L10n.format(
                        "editor.validation.header_duplicate",
                        resolvedHeader.normalizedName
                    )
                )
            }
        }
    }

    private func validateParserConfiguration() throws {
        switch draft.parser.kind {
        case .jsonPath:
            guard isJSONPathAvailable else {
                throw EditorValidationErrorV2(
                    L10n.string("editor.validation.json_required")
                )
            }
            try JSONPathParser.validate(draft.parser.jsonPath)
        case .javaScript:
            guard !draft.parser.scriptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EditorValidationErrorV2(
                    L10n.string("editor.validation.javascript_required")
                )
            }
        }
    }

    private func isSuccessfulHTTPResponse(_ response: HTTPResponseSnapshot) -> Bool {
        guard let statusCode = response.statusCode else { return true }
        return (200...299).contains(statusCode)
    }
}

private struct MonitorRuntimeStatusView: View {
    let runtime: MonitorRuntimeState
    let isRefreshing: Bool
    let nextRefreshAt: Date?
    let isEnabled: Bool
    let isSavedMonitor: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 24, height: 24)
                .background(statusColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(detail)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !isSavedMonitor { return L10n.string("runtime.unsaved") }
        if !isEnabled { return L10n.string("runtime.disabled") }
        if isRefreshing { return L10n.string("runtime.refreshing") }
        if runtime.consecutiveFailures >= 3 {
            return L10n.string("runtime.repeated_failure")
        }
        if runtime.consecutiveFailures > 0 {
            return L10n.format(
                "runtime.recent_failure",
                Int64(runtime.consecutiveFailures)
            )
        }
        if runtime.lastSuccessAt != nil { return L10n.string("runtime.healthy") }
        return L10n.string("runtime.awaiting_first_update")
    }

    private var detail: String {
        if !isSavedMonitor {
            return L10n.string("runtime.unsaved_detail")
        }
        if !isEnabled {
            return L10n.string("runtime.disabled_detail")
        }

        var parts: [String] = []
        if let error = runtime.lastError {
            parts.append(error.localizedDescription)
        }
        if runtime.lastError != nil, let lastAttemptAt = runtime.lastAttemptAt {
            parts.append(L10n.format("runtime.last_attempt", dateText(lastAttemptAt)))
        } else if let lastSuccessAt = runtime.lastSuccessAt {
            parts.append(L10n.format("runtime.last_success", dateText(lastSuccessAt)))
        }
        if !isRefreshing, let nextRefreshAt {
            parts.append(L10n.format("runtime.next_refresh", dateText(nextRefreshAt)))
        }
        if parts.isEmpty {
            return L10n.string("runtime.enabled_detail")
        }
        return parts.joined(separator: L10n.string("list.detail_separator"))
    }

    private var iconName: String {
        if !isSavedMonitor { return "square.and.arrow.down" }
        if !isEnabled { return "pause.fill" }
        if isRefreshing { return "arrow.triangle.2.circlepath" }
        if runtime.consecutiveFailures > 0 { return "exclamationmark.triangle.fill" }
        if runtime.lastSuccessAt != nil { return "checkmark.circle.fill" }
        return "clock.fill"
    }

    private var statusColor: Color {
        if !isSavedMonitor || !isEnabled { return .secondary }
        if isRefreshing { return .accentColor }
        if runtime.consecutiveFailures >= 3 { return .red }
        if runtime.consecutiveFailures > 0 { return .orange }
        if runtime.lastSuccessAt != nil { return .green }
        return .secondary
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(L10n.locale)
        )
    }
}

private struct ResponsePreviewView: View {
    let response: HTTPResponseSnapshot?
    let isLoading: Bool
    let isConfigurationStale: Bool
    let sourceLabel: String
    let latestRequestFailure: EditorRequestFailure?
    @State private var showsHTTPDetails = false

    private let panelBackground = Color(red: 0.12, green: 0.13, blue: 0.17)

    var body: some View {
        VStack(spacing: 0) {
            if let latestRequestFailure {
                latestFailureBanner(latestRequestFailure)
            }
            metadataBar

            ScrollView([.horizontal, .vertical]) {
                Text(bodyText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(response == nil ? 0.55 : 0.92))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .frame(minHeight: 132, maxHeight: 210)
            .background(panelBackground)

            DisclosureGroup(isExpanded: $showsHTTPDetails) {
                ScrollView(.horizontal) {
                    Text(
                        response?.fullHTTPDetails
                            ?? L10n.string("response.no_http_details")
                    )
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            } label: {
                HStack(spacing: 14) {
                    Text(L10n.string("response.http_details"))
                        .font(.subheadline.weight(.semibold))
                    Text(
                        response?.detailsSummary
                            ?? L10n.format("response.header_summary.zero", "HTTP")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.background.secondary.opacity(0.45))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        }
    }

    private func latestFailureBanner(_ failure: EditorRequestFailure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    response == nil
                        ? L10n.string("response.latest_request_failed")
                        : L10n.string("response.latest_request_failed_preserved")
                )
                    .font(.caption.weight(.semibold))
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(failure.message)
            }
            Spacer(minLength: 8)
            Text(
                failure.attemptedAt.formatted(
                    Date.FormatStyle(date: .omitted, time: .shortened)
                        .locale(L10n.locale)
                )
            )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.09))
        .accessibilityElement(children: .combine)
    }

    private var metadataBar: some View {
        HStack(spacing: 12) {
            Text(sourceLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if isConfigurationStale {
                Text(L10n.string("response.configuration_changed"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(responseTimeText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let statusText = response?.statusText {
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            Text(response?.contentType ?? L10n.string("response.unknown_type"))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.background.secondary, in: Capsule())
                .help(response?.contentType ?? L10n.string("response.no_content_type"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary.opacity(0.28))
    }

    private var bodyText: String {
        response?.bodyText ?? L10n.string("response.no_response")
    }

    private var responseTimeText: String {
        guard let date = response?.requestedAt else {
            return L10n.string("response.time_unavailable")
        }
        return L10n.format(
            "response.time",
            date.formatted(
                Date.FormatStyle(date: .numeric, time: .standard)
                    .locale(L10n.locale)
            )
        )
    }

    private var statusColor: Color {
        guard let statusCode = response?.statusCode else { return .secondary }
        return (200...299).contains(statusCode) ? .green : .red
    }
}

private struct EditorValidationErrorV2: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
