import Foundation

/// Доступ к ресурсам пакета (иконки, данные) без привязки к AppKit.
///
/// `Bundle.module` живёт внутри `ButtonSCore`, поэтому остальные модули
/// (в том числе исполняемый `ButtonSApp`) достают файлы через этот тип.
public enum Resources {
    /// Каталог `Icons` внутри бандла ресурсов.
    public static func iconsDirectory() -> URL? {
        let fm = FileManager.default

        // 1) SPM-бандл модуля: рядом лежит Icons как каталог-ресурс.
        if let bundleURL = Bundle.module.resourceURL {
            let direct = bundleURL.appendingPathComponent("Icons")
            if fm.fileExists(atPath: direct.path) { return direct }
            let nested = bundleURL.appendingPathComponent("Contents/Resources/Icons")
            if fm.fileExists(atPath: nested.path) { return nested }
        }

        // 2) установленное приложение: ресурсы рядом с бинарником.
        if let bundleURL = Bundle.main.resourceURL {
            let direct = bundleURL.appendingPathComponent("Icons")
            if fm.fileExists(atPath: direct.path) { return direct }
        }

        // 3) запуск из исходников (swift run / отладка).
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Icons")
        if fm.fileExists(atPath: source.path) { return source }

        return nil
    }

    /// Путь к конкретному файлу иконки.
    public static func icon(_ name: String) -> URL? {
        iconsDirectory()?.appendingPathComponent(name)
    }
}