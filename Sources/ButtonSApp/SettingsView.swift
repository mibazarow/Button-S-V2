import SwiftUI
import AppKit
import ButtonSCore
import ButtonSMac
import ButtonSVoice

// MARK: - Разделы

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, corrections, voice, dictionary, preview, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Общие"
        case .corrections: return "Исправления"
        case .voice: return "Голос"
        case .dictionary: return "Словари"
        case .preview: return "Проверка"
        case .about: return "О программе"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .corrections: return "text.badge.checkmark"
        case .voice: return "mic"
        case .dictionary: return "character.book.closed"
        case .preview: return "eye"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Разрешения, запуск, поведение"
        case .corrections: return "Раскладка, опечатки, правила письма"
        case .voice: return "Диктовка и распознавание на устройстве"
        case .dictionary: return "Подключённые наборы слов"
        case .preview: return "Как движок правит текст"
        case .about: return "Версия и сведения"
        }
    }
}

// MARK: - Карточки-обёртки

/// Секция настроек в стиле «карточка»: заголовок, подпись, содержимое.
struct SettingsCard<Content: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

/// Строка настройки: подпись слева, контрол справа.
struct SettingRow<Control: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                if let hint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
                .controlSize(.small)
        }
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}

// MARK: - Окно настроек

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: SettingsStore
    @State private var section: SettingsSection = .general
    @State private var testInput = "ghbdtn, превет"
    @State private var testOutput = ""
    @State private var testDetail: [String] = []

    init(controller: AppController) {
        self.controller = controller
        self.settings = controller.settings
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            content
        }
        .frame(width: 780, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { controller.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Пользователь мог выдать разрешение в системных настройках — перечитываем.
            controller.refreshPermissions()
        }
    }

    // MARK: Сайдбар

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Button-S")
                        .font(.system(size: 12, weight: .semibold))
                    Text(controller.isPaused ? "на паузе" : "работает")
                        .font(.system(size: 10))
                        .foregroundStyle(controller.isPaused ? .orange : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { item in
                    SidebarRow(
                        section: item,
                        selected: section == item,
                        action: { section = item }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(controller.permissionsOK ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(controller.permissionsOK ? "Доступ выдан" : "Нет доступа")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 196)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    // MARK: Контент

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(section.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 12) {
                    switch section {
                    case .general: generalSection
                    case .corrections: correctionsSection
                    case .voice: voiceSection
                    case .dictionary: dictionarySection
                    case .preview: previewSection
                    case .about: aboutSection
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }

    // MARK: Общие

    private var generalSection: some View {
        Group {
            SettingsCard(
                title: "Разрешения",
                caption: "Без «Универсального доступа» приложение не может править текст в других программах"
            ) {
                SettingRow(
                    title: controller.permissionsOK ? "Универсальный доступ выдан" : "Универсальный доступ не выдан",
                    hint: controller.permissionsOK
                        ? "Перехват клавиатуры и вставка работают"
                        : "Откройте системные настройки и включите Button-S в списке"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: controller.permissionsOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(controller.permissionsOK ? .green : .orange)
                        Button("Запросить") { controller.requestPermissions() }
                        Button("Настройки") { controller.openPrivacyPane("Privacy_Accessibility") }
                    }
                }
                DividerLine()
                SettingRow(
                    title: controller.micGranted ? "Микрофон разрешён" : "Микрофон не разрешён",
                    hint: controller.micGranted
                        ? "Голосовой ввод готов к работе"
                        : controller.micStatusText
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: controller.micGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(controller.micGranted ? .green : .orange)
                        Button("Запросить") { controller.requestMicrophone() }
                        Button("Настройки") { controller.openPrivacyPane("Privacy_Microphone") }
                    }
                }
            }

            SettingsCard(title: "Запуск", caption: "Как приложение ведёт себя при старте системы") {
                SettingRow(title: "Запускать при входе") {
                    Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
                }
                DividerLine()
                SettingRow(
                    title: "Уведомлять об исправлении",
                    hint: "Короткий баннер в правом верхнем углу"
                ) {
                    Toggle("", isOn: $settings.notifyOnFix).labelsHidden()
                }
            }

            SettingsCard(title: "Сейчас", caption: "Состояние движка и последнее действие") {
                SettingRow(title: "Статус") {
                    Text(controller.isPaused ? "Пауза" : "Работает")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(controller.isPaused ? .orange : .green)
                }
                DividerLine()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Последняя правка")
                        .font(.system(size: 12))
                    Text(controller.lastChange)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            if !controller.history.isEmpty {
                SettingsCard(title: "История", caption: "Последние \(controller.history.count) правок") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(controller.history.prefix(8).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                Text(item.from)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                Text(item.to)
                                Spacer()
                            }
                            .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
        }
    }

    // MARK: Исправления

    private var correctionsSection: some View {
        Group {
            SettingsCard(title: "Раскладка", caption: "Клавиши нажаты в одной раскладке, а слово нужно в другой") {
                SettingRow(
                    title: "Исправлять раскладку",
                    hint: "ghbdtn → привет"
                ) {
                    Toggle("", isOn: $settings.layoutEnabled).labelsHidden()
                }
                DividerLine()
                SettingRow(
                    title: "Переключать раскладку",
                    hint: "Системная раскладка меняется после правки слова"
                ) {
                    Toggle("", isOn: $settings.autoSwitchLayout).labelsHidden()
                }
                .disabled(!settings.layoutEnabled)
            }

            SettingsCard(title: "Опечатки", caption: "Поиск по словарю с учётом соседних клавиш") {
                SettingRow(title: "Режим") {
                    Picker("", selection: $settings.typoMode) {
                        Text("Авто").tag("auto")
                        Text("Подсказка").tag("suggest")
                        Text("Выкл").tag("off")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                DividerLine()
                SettingRow(
                    title: "Допуск",
                    hint: "Сколько правок разрешено в слове"
                ) {
                    Picker("", selection: $settings.typoMaxDistance) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                }
                BlueprintNote("Автоправка срабатывает только на уверенных совпадениях, редкие слова не трогаются")
            }

            SettingsCard(title: "Правила письма", caption: "Что делать после пробела, точки и переноса строки") {
                SettingRow(
                    title: "Чинить залипший Shift",
                    hint: "Слово набрано с заглавной посреди предложения"
                ) {
                    Toggle("", isOn: $settings.shiftFixEnabled).labelsHidden()
                }
                DividerLine()
                SettingRow(
                    title: "Заглавная после точки",
                    hint: "Поднимать первую букву после точки, двоеточия и Enter"
                ) {
                    Toggle("", isOn: $settings.capitalizationEnabled).labelsHidden()
                }
                DividerLine()
                SettingRow(
                    title: "Продолжать списки",
                    hint: "Enter после «—» или «1.» добавляет следующий пункт"
                ) {
                    Toggle("", isOn: $settings.listsEnabled).labelsHidden()
                }
            }
        }
    }

    // MARK: Голос

    // MARK: Модель

    @ViewBuilder
    private var modelCard: some View {
        let model = controller.currentVoiceModel
        SettingsCard(
            title: "Модель распознавания",
            caption: "Скачивается один раз и работает без интернета"
        ) {
            switch controller.modelState {
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Скачивание \(model.title)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("Хранится в ~/Library/Application Support/com.button.v2/Models")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Отмена") { controller.cancelVoiceModelDownload() }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)

            case .ready:
                SettingRow(
                    title: "Модель скачана",
                    hint: controller.downloadedBytes > 0
                        ? "Занято на диске: \(Self.formatBytes(controller.downloadedBytes))"
                        : "Готова к работе"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Удалить") { controller.deleteVoiceModel() }
                    }
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Не удалось скачать")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button("Скачать заново") { controller.downloadVoiceModel() }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)

            default:
                SettingRow(
                    title: "Модель не скачана",
                    hint: "Без неё голосовой ввод не работает. Вес: \(model.approxSize)"
                ) {
                    Button("Скачать") { controller.downloadVoiceModel() }
                }
            }
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var voiceSection: some View {
        Group {
            SettingsCard(title: "Диктовка", caption: "Распознавание идёт локально, без облака") {
                SettingRow(title: "Включить голосовой ввод") {
                    Toggle("", isOn: $settings.voiceEnabled).labelsHidden()
                }
                DividerLine()
                SettingRow(title: "Клавиша удержания") {
                    Picker("", selection: $settings.voiceKey) {
                        Text("Правый Shift").tag("ShiftRight")
                        Text("Левый Shift").tag("ShiftLeft")
                    }
                    .frame(width: 150)
                }
                .disabled(!settings.voiceEnabled)
                DividerLine()
                SettingRow(title: "Модель") {
                    Picker("", selection: $settings.whisperModel) {
                        ForEach(SpeechRecognizer.ModelSize.allCases, id: \.self) { size in
                            Text("\(size.title)  \(size.approxSize)").tag(size.rawValue)
                        }
                    }
                    .frame(width: 210)
                    .onChange(of: settings.whisperModel) { _, _ in
                        controller.voiceModelChanged()
                    }
                }
                .disabled(!settings.voiceEnabled)
                DividerLine()
                SettingRow(title: "Язык") {
                    Picker("", selection: $settings.voiceLanguage) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                        Text("Авто").tag("auto")
                    }
                    .frame(width: 130)
                }
                .disabled(!settings.voiceEnabled)
            }

            modelCard

            SettingsCard(title: "Обработка", caption: "Что делается с распознанным текстом") {
                SettingRow(
                    title: "Расставлять пунктуацию",
                    hint: "Whisper ставит точки и запятые сам"
                ) {
                    Toggle("", isOn: $settings.autoPunctuation).labelsHidden()
                }
                DividerLine()
                SettingRow(
                    title: "Убирать слова-затычки",
                    hint: "«эээ», «ну», «как бы» вырезаются"
                ) {
                    Toggle("", isOn: $settings.removeFillers).labelsHidden()
                }
            }

            if let error = controller.voiceError {
                SettingsCard(title: "Ошибка", caption: "Голосовой ввод сообщил о проблеме") {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            BlueprintNote("Первый запуск скачивает модель (~1.6 ГБ для large-v3-turbo). Файл кладётся в ~/Library/Application Support/Button-S/Models.")
        }
    }

    // MARK: Словари

    private var dictionarySection: some View {
        Group {
            SettingsCard(title: "Подключённые наборы", caption: "Данные читаются с диска при старте") {
                VStack(alignment: .leading, spacing: 8) {
                    DictionaryRow(name: "Морфология русского", file: "ru_morph.txt", note: "словоформы для раскладки и опечаток")
                    DividerLine()
                    DictionaryRow(name: "Частоты русского", file: "ru_30k.txt", note: "30 000 слов, сортировка по частоте")
                    DividerLine()
                    DictionaryRow(name: "Частоты английского", file: "en_30k.txt", note: "30 000 слов, сортировка по частоте")
                }
            }

            BlueprintNote("Наборы лежат в Resources/Data внутри бандла. Перезапуск приложения подхватывает изменения.")
        }
    }

    // MARK: Проверка

    private var previewSection: some View {
        Group {
            SettingsCard(title: "Входной текст", caption: "Наберите фразу и нажмите Enter") {
                TextField("Например: ghbdtn, превет", text: $testInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { runPreview() }
                HStack {
                    Button("Проверить") { runPreview() }
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Пример") { testInput = "ghbdtn, превет"; runPreview() }
                    Spacer()
                }
            }

            if !testOutput.isEmpty {
                SettingsCard(title: "Результат", caption: "Так движок увидит текст после правок") {
                    Text(testOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if !testDetail.isEmpty {
                    SettingsCard(title: "Что сработало") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(testDetail.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: О программе

    private var aboutSection: some View {
        Group {
            SettingsCard(title: "Button-S") {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Версия 2.0")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Автозамена раскладки, опечаток и правил письма для macOS")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Работает офлайн, данные не покидают машину")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: "Горячие клавиши", caption: "Действуют в любом приложении") {
                HotkeyRow(keys: "⌘P", action: "Пауза / продолжить")
                DividerLine()
                HotkeyRow(keys: "⌘L", action: "Сменить раскладку выделенного")
                DividerLine()
                HotkeyRow(keys: "⌘,", action: "Открыть настройки")
            }
        }
    }

    // MARK: Логика проверки

    private func runPreview() {
        let result = PreviewCorrector.run(
            testInput,
            layoutEnabled: settings.layoutEnabled,
            typosEnabled: settings.typosEnabled,
            typoMode: settings.typoMode,
            typoMaxDistance: settings.typoMaxDistance
        )
        testOutput = result.text
        testDetail = result.details
    }
}

// MARK: - Мелкие компоненты

struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(section.title)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
    }
}

struct BlueprintNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

struct DictionaryRow: View {
    let name: String
    let file: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12))
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(file)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }
}

struct HotkeyRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}
