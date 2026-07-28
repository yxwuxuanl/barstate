import AppKit
import BarStateCore
import SwiftUI

struct MonitorEditorViewV2: View {
    @State private var draft: Monitor
    @State private var refreshIntervalValue: Double
    @State private var baselineTestConfiguration: EditorTestConfiguration
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
    @State private var isBasicPasswordRevealed = false
    @State private var showsAdvancedRequestSettings: Bool
    @State private var previewValue: Double?

    let isNewMonitor: Bool
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
        editableMonitor.parser.scriptBody = JavaScriptEvaluator.normalizingResponseJSDoc(
            in: monitor.parser.scriptBody
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
        _baselineTestConfiguration = State(
            initialValue: EditorTestConfiguration(monitor: editableMonitor)
        )
        _baselineConfiguration = State(
            initialValue: EditorEditableConfiguration(monitor: editableMonitor)
        )
        _requiresInitialSuccessfulTest = State(initialValue: requiresInitialSuccessfulTest)
        _showsAdvancedRequestSettings = State(
            initialValue: editableMonitor.authentication.kind != .none
                || !editableMonitor.requestHeaders.isEmpty
                || editableMonitor.requestTimeout != Monitor.defaultRequestTimeout
        )
        _previewValue = State(initialValue: monitor.runtime.lastValue)
        _response = State(initialValue: monitor.runtime.lastResponse)
        _responseConfiguration = State(
            initialValue: monitor.runtime.lastResponse == nil
                ? nil
                : EditorRequestConfiguration(monitor: editableMonitor)
        )
        _requestFailure = State(
            initialValue: Self.runtimeRequestFailure(from: monitor.runtime)
        )

        isNewMonitor = requiresInitialSuccessfulTest
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
                        if isNewMonitor {
                            MonitorCreationProgressView(
                                sourceKind: draft.sourceKind,
                                connectionComplete: connectionStageComplete,
                                extractionComplete: extractionStageComplete,
                                displayComplete: displayStageComplete
                            )
                        }
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
                            menuBarPreview
                        }

                        settingsSection(requestSectionTitle) {
                            requestConfigurationSection
                        }

                        if draft.sourceKind == .httpAPI, !isNewMonitor || response != nil {
                            settingsSection(L10n.string("editor.section.parser")) {
                                parserSection
                            }
                            .id("parser-section")
                        } else if draft.sourceKind == .httpAPI {
                            Label(
                                L10n.string("editor.waiting_for_response"),
                                systemImage: "arrow.up.circle"
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, EditorFormLayoutMetrics.labelWidth + 16)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--preview-response") {
                        DispatchQueue.main.async {
                            proxy.scrollTo("response-preview", anchor: .bottom)
                        }
                    } else if arguments.contains("--preview-parser") {
                        DispatchQueue.main.async {
                            proxy.scrollTo("parser-section", anchor: .top)
                        }
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
                requestFailure = EditorRequestFailure(
                    message: message,
                    attemptedAt: Date(),
                    requestDuration: 10
                )
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
            if isNewMonitor {
                previewValue = nil
            }
        }
        .onChange(of: draft.parser) {
            parseTask?.cancel()
            parseTask = nil
            isParsing = false
            resetParseFeedback()
            savedMessage = nil
            if isNewMonitor {
                previewValue = nil
            }
        }
        .onChange(of: draft.authentication.kind) {
            isBasicPasswordRevealed = false
        }
        .onChange(of: currentEditableConfiguration) {
            savedMessage = nil
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: latestRuntime.lastResponse) { _, newResponse in
            guard !usesManualResponse, let newResponse else { return }
            response = newResponse
            responseConfiguration = currentRequestConfiguration
        }
        .onChange(of: latestRuntime.lastAttemptAt) {
            guard !usesManualResponse else { return }
            requestFailure = Self.runtimeRequestFailure(from: latestRuntime)
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

    private var menuBarPreview: some View {
        HStack(spacing: 12) {
            Label(
                L10n.string("editor.menu_bar_preview"),
                systemImage: "menubar.rectangle"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Spacer(minLength: 20)
            Text(previewDisplayText)
                .font(.system(.body, design: .rounded).weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 280, alignment: .trailing)
                .help(previewDisplayText)
        }
        .padding(.leading, EditorFormLayoutMetrics.labelWidth + 16)
        .accessibilityElement(children: .combine)
    }

    private var previewDisplayText: String {
        let valueText = previewValue.map { NumberDisplayFormatter.string(from: $0) } ?? "--"
        return draft.displayTemplate.replacingOccurrences(
            of: Monitor.valuePlaceholder,
            with: valueText
        )
    }

    private var connectionStageComplete: Bool {
        if draft.sourceKind == .prometheus {
            return parseSucceeded
        }
        guard let response else { return false }
        return requestFailure == nil && isSuccessfulHTTPResponse(response)
    }

    private var extractionStageComplete: Bool {
        parseSucceeded
    }

    private var displayStageComplete: Bool {
        extractionStageComplete && draft.displayTemplate.contains(Monitor.valuePlaceholder)
    }

    private var requestSectionTitle: String {
        draft.sourceKind == .prometheus
            ? L10n.string("editor.section.query")
            : L10n.string("editor.section.request")
    }

    private var requestConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            formGrid {
                GridRow {
                    fieldLabel(L10n.string("editor.data_source"))
                    Picker(L10n.string("editor.data_source"), selection: $draft.sourceKind) {
                        ForEach(MonitorSourceKind.allCases) { sourceKind in
                            Text(sourceKind.displayName).tag(sourceKind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                }

                GridRow(alignment: .top) {
                    fieldLabel(endpointLabel)
                    VStack(alignment: .leading, spacing: 7) {
                        TextField(endpointPlaceholder, text: $draft.urlString)
                            .textContentType(.URL)
                            .accessibilityLabel(endpointLabel)
                        if draft.sourceKind == .prometheus {
                            Text(L10n.string("editor.prometheus_endpoint_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if draft.sourceKind == .prometheus {
                    GridRow(alignment: .top) {
                        fieldLabel("PromQL")
                        VStack(alignment: .leading, spacing: 7) {
                            TextEditor(text: $draft.promQL)
                                .font(.system(.body, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 82)
                                .padding(6)
                                .background(
                                    .background.secondary,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.separator.opacity(0.7), lineWidth: 1)
                                }
                                .accessibilityLabel("PromQL")
                            Text(L10n.string("editor.prometheus_query_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

                GridRow(alignment: .top) {
                    Color.clear.frame(width: EditorFormLayoutMetrics.labelWidth, height: 1)
                    advancedRequestToggle
                }

                if showsAdvancedRequestSettings {
                    GridRow {
                        fieldLabel(L10n.string("editor.authentication"))
                        Picker(
                            L10n.string("editor.authentication"),
                            selection: $draft.authentication.kind
                        ) {
                            Text(L10n.string("editor.authentication_none"))
                                .tag(HTTPAuthenticationKind.none)
                            Text("Basic Authentication")
                                .tag(HTTPAuthenticationKind.basic)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 280)
                    }

                    if draft.authentication.kind == .basic {
                        GridRow {
                            fieldLabel(L10n.string("editor.basic_auth_username"))
                            TextField(
                                L10n.string("editor.basic_auth_username_placeholder"),
                                text: $draft.authentication.username
                            )
                            .textContentType(.username)
                            .accessibilityLabel(L10n.string("editor.basic_auth_username"))
                        }

                        GridRow(alignment: .top) {
                            fieldLabel(L10n.string("editor.basic_auth_password"))
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    Group {
                                        if isBasicPasswordRevealed {
                                            TextField(
                                                L10n.string("editor.basic_auth_password_placeholder"),
                                                text: $draft.authentication.password
                                            )
                                        } else {
                                            SecureField(
                                                L10n.string("editor.basic_auth_password_placeholder"),
                                                text: $draft.authentication.password
                                            )
                                        }
                                    }
                                    .textContentType(.password)
                                    .accessibilityLabel(L10n.string("editor.basic_auth_password"))

                                    Button {
                                        isBasicPasswordRevealed.toggle()
                                    } label: {
                                        Image(systemName: isBasicPasswordRevealed ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderless)
                                    .frame(
                                        width: RequestHeaderLayoutMetrics.actionSize,
                                        height: RequestHeaderLayoutMetrics.actionSize
                                    )
                                    .help(
                                        isBasicPasswordRevealed
                                            ? L10n.string("editor.basic_auth_hide_password")
                                            : L10n.string("editor.basic_auth_show_password")
                                    )
                                    .accessibilityLabel(
                                        isBasicPasswordRevealed
                                            ? L10n.string("editor.basic_auth_hide_password")
                                            : L10n.string("editor.basic_auth_show_password")
                                    )
                                }

                                Text(L10n.string("editor.basic_auth_storage_help"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if showsAdvancedRequestSettings {
                    GridRow {
                        fieldLabel(L10n.string("editor.request_timeout"))
                        HStack(spacing: 8) {
                            TextField(
                                L10n.string("editor.numeric_value"),
                                value: $draft.requestTimeout,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .frame(width: 120)
                            .accessibilityLabel(
                                L10n.string("editor.request_timeout_accessibility")
                            )
                            Text(L10n.string("monitor.interval.seconds"))
                                .foregroundStyle(.secondary)
                            Text(L10n.string("editor.request_timeout_help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if showsAdvancedRequestSettings {
                requestHeadersSection
            }
            requestActionRow
            if response != nil || isRequesting || requestFailure != nil {
                ResponsePreviewView(
                    response: response,
                    isLoading: isRequesting,
                    isConfigurationStale: isResponseStale,
                    sourceLabel: responseSourceLabel,
                    latestRequestFailure: requestFailure
                )
                .id("response-preview")
            }
        }
    }

    private var endpointLabel: String {
        draft.sourceKind == .prometheus
            ? L10n.string("editor.prometheus_address")
            : "HTTPS URL"
    }

    private var advancedRequestToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                showsAdvancedRequestSettings.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(showsAdvancedRequestSettings ? 90 : 0))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("editor.advanced_request"))
                        .font(.subheadline.weight(.semibold))
                    if !showsAdvancedRequestSettings {
                        Text(L10n.string("editor.advanced_request_help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            showsAdvancedRequestSettings
                ? L10n.string("common.expanded")
                : L10n.string("common.collapsed")
        )
    }

    private var endpointPlaceholder: String {
        draft.sourceKind == .prometheus
            ? "https://prometheus.example.com"
            : "https://api.example.com/value?ts=${TIMESTAMP}"
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

            ForEach(draft.requestHeaders) { headerSnapshot in
                let headerBinding = stableRequestHeaderBinding(
                    for: headerSnapshot,
                    in: $draft.requestHeaders
                )
                let header = headerBinding.wrappedValue
                HStack(spacing: RequestHeaderLayoutMetrics.columnSpacing) {
                    TextField("Authorization", text: headerBinding.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(
                            L10n.string("editor.request_header_name_accessibility")
                        )

                    Group {
                        if !header.hasSensitiveValue || revealedHeaderIDs.contains(header.id) {
                            TextField("Bearer ${TIMESTAMP}", text: headerBinding.value)
                        } else {
                            SecureField("Bearer ${TIMESTAMP}", text: headerBinding.value)
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
                        draft.requestHeaders.removeAll { $0.id == headerSnapshot.id }
                        revealedHeaderIDs.remove(headerSnapshot.id)
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
                    revealedHeaderIDs.remove(headerSnapshot.id)
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
            Button(requestActionTitle) {
                if draft.sourceKind == .prometheus {
                    testPrometheusQuery()
                } else {
                    testRequest()
                }
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
            } else if draft.sourceKind == .prometheus, let parseMessage {
                Label(
                    parseMessage,
                    systemImage: parseSucceeded
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(parseSucceeded ? Color.green : Color.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var requestActionTitle: String {
        if isRequesting {
            return draft.sourceKind == .prometheus
                ? L10n.string("editor.querying")
                : L10n.string("editor.requesting")
        }
        return draft.sourceKind == .prometheus
            ? L10n.string("editor.test_query")
            : L10n.string("editor.test_request")
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
                Color.clear.frame(width: EditorFormLayoutMetrics.labelWidth, height: 1)
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
            .lineLimit(1)
            .frame(width: EditorFormLayoutMetrics.labelWidth, alignment: .trailing)
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
        if draft.sourceKind == .prometheus {
            guard response != nil else {
                return L10n.string("editor.prometheus_response_preview")
            }
            return usesManualResponse
                ? L10n.string("editor.manual_query_response")
                : L10n.string("editor.latest_query_response")
        } else {
            guard response != nil else { return L10n.string("editor.response_preview") }
            return usesManualResponse
                ? L10n.string("editor.manual_response")
                : L10n.string("editor.latest_response")
        }
    }

    private var hasUnsavedChanges: Bool {
        requiresInitialSuccessfulTest || currentEditableConfiguration != baselineConfiguration
    }

    private var switchesApplyImmediately: Bool {
        onSwitchesChange != nil
    }

    private var requiresSuccessfulTest: Bool {
        guard !requiresInitialSuccessfulTest else { return true }
        if draft.sourceKind == .prometheus {
            return currentTestConfiguration != baselineTestConfiguration
        }
        return currentTestConfiguration.parser != baselineTestConfiguration.parser
    }

    private var isSuccessfulTestRequiredAndMissing: Bool {
        requiresSuccessfulTest && successfulTestConfiguration != currentTestConfiguration
    }

    private var saveRequirementMessage: String? {
        guard isSuccessfulTestRequiredAndMissing else { return nil }
        if requiresInitialSuccessfulTest {
            return draft.sourceKind == .prometheus
                ? L10n.string("editor.new_prometheus_monitor_test_required")
                : L10n.string("editor.new_monitor_test_required")
        }
        return draft.sourceKind == .prometheus
            ? L10n.string("editor.prometheus_retest_required")
            : L10n.string("editor.parser_retest_required")
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
        guard draft.sourceKind == .httpAPI,
              response != nil,
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
                draft.parser.scriptBody = JavaScriptEvaluator.normalizingResponseJSDoc(
                    in: draft.parser.scriptBody
                )
                if receivedResponse.bodyKind != .json, draft.parser.kind == .jsonPath {
                    draft.parser.kind = .javaScript
                }
            }
            if let error = outcome.error {
                requestFailure = EditorRequestFailure(
                    message: error.localizedDescription,
                    attemptedAt: outcome.requestedAt,
                    requestDuration: outcome.requestDuration
                )
            } else {
                requestFailure = nil
            }
            requestMessage = outcome.error?.localizedDescription
        }
    }

    private func testPrometheusQuery() {
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
        let requestConfiguration = currentRequestConfiguration
        let testConfiguration = currentTestConfiguration

        requestTask = Task {
            let outcome = await APIClient().fetchValue(for: monitor)
            guard !Task.isCancelled else { return }
            isRequesting = false
            requestTask = nil

            if let receivedResponse = outcome.response {
                response = receivedResponse
                responseConfiguration = requestConfiguration
                usesManualResponse = true
            }

            switch outcome.result {
            case let .success(value):
                parseSucceeded = true
                previewValue = value
                requestFailure = nil
                parseMessage = L10n.format(
                    "editor.prometheus_query_success",
                    NumberDisplayFormatter.string(from: value)
                )
                successfulTestConfiguration = testConfiguration

            case let .failure(error):
                parseSucceeded = false
                if isNewMonitor { previewValue = nil }
                parseMessage = error.localizedDescription
                successfulTestConfiguration = nil
                if let response = outcome.response, isSuccessfulHTTPResponse(response) {
                    requestFailure = nil
                } else {
                    requestMessage = error.localizedDescription
                    requestFailure = EditorRequestFailure(
                        message: error.localizedDescription,
                        attemptedAt: outcome.requestedAt,
                        requestDuration: outcome.requestDuration
                    )
                }
            }
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
                    previewValue = value
                    parseMessage = valueText
                    successfulTestConfiguration = configuration
                } else {
                    parseSucceeded = false
                    if isNewMonitor { previewValue = nil }
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
                if isNewMonitor { previewValue = nil }
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
            if draft.authentication.kind == .none {
                draft.authentication = .init()
            }
            draft.requestHeaders = draft.requestHeaders.map { header in
                var normalized = header
                normalized.name = header.normalizedName
                return normalized
            }
            validationMessage = nil
            savedMessage = L10n.string("editor.saved")
            baselineTestConfiguration = EditorTestConfiguration(monitor: draft)
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
        guard draft.requestTimeout.isFinite,
              draft.requestTimeout >= Monitor.minimumRequestTimeout
        else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.request_timeout_min")
            )
        }
        guard draft.requestTimeout <= Monitor.maximumRequestTimeout else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.request_timeout_max")
            )
        }
        guard draft.displayTemplate.contains(Monitor.valuePlaceholder) else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.template_value_required")
            )
        }

        try validateRequestConfiguration()
        if draft.sourceKind == .httpAPI {
            try validateParserConfiguration()
        }

        guard !isSuccessfulTestRequiredAndMissing else {
            throw EditorValidationErrorV2(
                saveRequirementMessage ?? L10n.string("editor.validation.test_required")
            )
        }
    }

    private func validateRequestConfiguration() throws {
        guard draft.requestTimeout.isFinite,
              draft.requestTimeout >= Monitor.minimumRequestTimeout,
              draft.requestTimeout <= Monitor.maximumRequestTimeout
        else {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.request_timeout_range")
            )
        }

        let validationDate = Date()
        let resolvedURLString = RequestTemplateResolver.resolve(draft.urlString, at: validationDate)
        guard let components = URLComponents(string: resolvedURLString),
              HTTPRequestBuilder.isSupportedEndpoint(
                  components,
                  allowsLoopbackHTTP: draft.sourceKind == .prometheus
              )
        else {
            throw EditorValidationErrorV2(
                draft.sourceKind == .prometheus
                    ? L10n.string("editor.validation.valid_prometheus_url")
                    : L10n.string("editor.validation.valid_https_url")
            )
        }

        if draft.sourceKind == .prometheus,
           draft.promQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.promql_required")
            )
        }

        if draft.authentication.kind == .basic,
           draft.authentication.username.contains(":")
        {
            throw EditorValidationErrorV2(
                L10n.string("editor.validation.basic_auth_username_colon")
            )
        }

        var headerNames: Set<String> = draft.authentication.kind == .basic
            ? ["authorization"]
            : []
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
            if resolvedHeader.normalizedName.caseInsensitiveCompare("Authorization") == .orderedSame,
               draft.authentication.kind == .basic
            {
                throw EditorValidationErrorV2(
                    L10n.string("editor.validation.authorization_conflict")
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

    private static func runtimeRequestFailure(
        from runtime: MonitorRuntimeState
    ) -> EditorRequestFailure? {
        guard let error = runtime.lastError, let attemptedAt = runtime.lastAttemptAt else {
            return nil
        }
        return EditorRequestFailure(
            message: error.localizedDescription,
            attemptedAt: attemptedAt,
            requestDuration: runtime.lastRequestDuration
        )
    }
}

private struct EditorValidationErrorV2: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
